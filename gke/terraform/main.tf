terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.46.0"
    }
  }
  required_version = ">= 0.14"
}

provider "google" {
  project     = var.gcp_project
  region      = var.gcp_region
  credentials = var.gcp_key_path
}


###############
# VPC Network #
###############

resource "google_compute_network" "vpc" {
  name = "${var.demo_name}-vpc"
  #  name                    = "eva-eck-vpc"
  auto_create_subnetworks = "false"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  #  name          = "eva-eck-subnet"
  name          = "${var.demo_name}-subnet"
  region        = var.gcp_region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}

####################
# Public static IP #
####################
resource "google_compute_address" "default" {
  #  name   = "eva-eck-static-ip-address"
  name   = "${var.demo_name}-static-ip-address"
  region = var.gcp_region
}

output "ingress_static_ip" {
  value       = google_compute_address.default.address
  description = "Static IP address for exposing Kibana"
}

###############
# GKE cluster #
###############

# K8s Cluster
data "google_client_config" "default" {}

resource "google_container_cluster" "primary" {
  #  name     = "eva-eck-gke"
  name               = "${var.demo_name}-gke"
  location           = var.gcp_region
  initial_node_count = 1
  network            = google_compute_network.vpc.name
  subnetwork         = google_compute_subnetwork.subnet.name

  resource_labels = jsondecode(var.labels)

  # Manage the node pool separately
  remove_default_node_pool = true
}

# Separately Managed Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = var.gcp_region
  cluster    = google_container_cluster.primary.name
  node_count = var.number_of_nodes

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    # preemptible  = true
    machine_type = "n1-standard-2"
    tags         = ["gke-node", "${var.demo_name}-gke"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}

output "kubernetes_cluster_region" {
  value       = var.gcp_region
  description = "GKE Cluster Region"
}

output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
}

################
# DNS A Record #
################
data "google_dns_managed_zone" "gke_zone" {
  name = var.dns_managed_zone_name # The name of the existing managed zone
}

resource "google_dns_record_set" "a" {
  managed_zone = data.google_dns_managed_zone.gke_zone.name
  name         = var.dns_hostname
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.default.address]
}
