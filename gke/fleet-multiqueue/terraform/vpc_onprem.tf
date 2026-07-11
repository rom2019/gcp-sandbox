# On-premise Simulation VPC Network
resource "google_compute_network" "vpc_onprem" {
  name                    = "vpc-onprem-simulation"
  auto_create_subnetworks = false
  depends_on              = [time_sleep.wait_for_org_policy]
}

resource "google_compute_subnetwork" "sub_onprem_gke" {
  name                     = "sub-onprem-gke"
  ip_cidr_range            = "192.168.10.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc_onprem.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "192.168.64.0/18"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "192.168.128.0/20"
  }
}

# Firewall rules for On-premise VPC
resource "google_compute_firewall" "allow_internal_onprem" {
  name    = "allow-internal-onprem"
  network = google_compute_network.vpc_onprem.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["192.168.0.0/16", "10.0.0.0/16"] # Allow from Cloud VPC via VPN
}

resource "google_compute_router_nat" "nat_onprem" {
  name                               = "nat-onprem"
  router                             = google_compute_router.router_onprem.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

