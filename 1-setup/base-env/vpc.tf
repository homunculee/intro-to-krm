resource "google_compute_network" "vpc_network" {
    project = var.project_id 
    name = "cymbal-network"
}

resource "google_compute_subnetwork" "public-subnetwork" {
    project = var.project_id 
    name = "cymbal-subnetwork"
    ip_cidr_range = "10.2.0.0/16"
    region = "us-east1"
    network = google_compute_network.vpc_network.name
}

resource "google_compute_network" "peering_network" {
  project = var.project_id 
  name = "cymbal-peering-network"
}

resource "google_compute_global_address" "private_ip_alloc" {
  project = var.project_id 
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.peering_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.peering_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}