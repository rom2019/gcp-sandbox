# Cloud VPC Network
resource "google_compute_network" "vpc_cloud" {
  name                    = "vpc-cloud-burst"
  auto_create_subnetworks = false
  depends_on              = [time_sleep.wait_for_org_policy]
}

resource "google_compute_subnetwork" "sub_cloud_gke" {
  name                     = "sub-cloud-gke"
  ip_cidr_range            = "10.1.0.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc_cloud.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

# Firewall rules for Cloud VPC
resource "google_compute_firewall" "allow_internal_cloud" {
  name    = "allow-internal-cloud"
  network = google_compute_network.vpc_cloud.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/16", "192.168.0.0/16"] # Allow from On-prem VPC via VPN
}

resource "google_compute_router_nat" "nat_cloud" {
  name                               = "nat-cloud"
  router                             = google_compute_router.router_cloud.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

