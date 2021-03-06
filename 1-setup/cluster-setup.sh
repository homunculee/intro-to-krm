#!/bin/bash 


########### VARIABLES  ##################################
if [[ -z "$PROJECT_ID" ]]; then
    echo "Must provide PROJECT_ID in environment" 1>&2
    exit 1
fi


# Anthos registration 
export MEMBERSHIP_NAME="anthos-membership"
export SERVICE_ACCOUNT_NAME="register-sa"

# Cymbal app 
export KSA_NAME="cymbal-ksa"
export GSA_NAME="cymbal-gsa"

############################################################

register_cluster () {
    CLUSTER_NAME=$1 
    CLUSTER_ZONE=$2 
    echo "π Registering cluster to Anthos: $CLUSTER_NAME, zone: $CLUSTER_ZONE" 
    kubectx ${CLUSTER_NAME} 

    URI="https://container.googleapis.com/v1/projects/${PROJECT_ID}/zones/${CLUSTER_ZONE}/clusters/${CLUSTER_NAME}"
    gcloud beta container hub memberships register ${CLUSTER_NAME} \
    --gke-uri=${URI} \
    --enable-workload-identity
}

setup_cluster () {
    CLUSTER_NAME=$1 
    CLUSTER_ZONE=$2 
    echo "βΈοΈ Setting up cluster: $CLUSTER_NAME, zone: $CLUSTER_ZONE" 
    gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${CLUSTER_ZONE} --project ${PROJECT_ID} 
    kubectx ${CLUSTER_NAME}=. 

    echo "π‘ Creating a Kubernetes Service Account (KSA) for each CymbalBank namespace..."
    declare -a NAMESPACES=("balancereader" "transactionhistory" "ledgerwriter" "contacts" "userservice" "frontend" "loadgenerator")

    for ns in "${NAMESPACES[@]}"
    do
        echo "****** π Setting up namespace: ${ns} ********"
        # boostrap namespace 
        kubectl create namespace $ns 

        # boostrap ksa 
        kubectl create serviceaccount --namespace $ns $KSA_NAME

        # connect KSA to GSA (many KSAs to 1 GSA)
        echo "βοΈ Allowing KSA: ${KSA_NAME} to act as GSA: ${GSA_NAME}"
        kubectl annotate serviceaccount \
            --namespace $ns \
            $KSA_NAME \
            iam.gke.io/gcp-service-account=$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com
        
        gcloud iam service-accounts add-iam-policy-binding \
            --role roles/iam.workloadIdentityUser \
            --member "serviceAccount:${PROJECT_ID}.svc.id.goog[$ns/$KSA_NAME]" \
            $GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com

        # create cloud SQL secrets. cluster and instance names are the same, ie. cymbal-dev is the name of both the dev GKE cluster and the dev Cloud SQL DB  
        echo "π Creating Cloud SQL user secret for Instance: ${CLUSTER_NAME}"
        INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe $CLUSTER_NAME --format='value(connectionName)')
        kubectl create secret -n ${ns} generic cloud-sql-admin \
            --from-literal=username=admin --from-literal=password=admin \
            --from-literal=connectionName=${INSTANCE_CONNECTION_NAME}  
    done 
    echo "β­οΈ Done with cluster: ${CLUSTER_NAME}"
    }

# kubeconfig for admin cluster 
gcloud config set project ${PROJECT_ID}

echo "βοΈ  Connecting to the admin cluster for later..."
gcloud container clusters get-credentials cymbal-admin --zone us-central1-f --project ${PROJECT_ID} 
kubectx cymbal-admin=. 

echo "Enabling Anthos APIs..."
gcloud services enable anthos.googleapis.com 

# Set up clusters for the CymbalBank app 
setup_cluster "cymbal-dev" "us-east1-c" 
setup_cluster "cymbal-staging" "us-central1-a" 
setup_cluster "cymbal-prod" "us-west1-a"

# Register all 4 clusters to the Anthos dashboard
register_cluster "cymbal-dev" "us-east1-c" 
register_cluster "cymbal-staging" "us-central1-a" 
register_cluster "cymbal-prod" "us-west1-a"
register_cluster "cymbal-admin" "us-central1-f"

echo "β GKE Cluster Setup Complete."



