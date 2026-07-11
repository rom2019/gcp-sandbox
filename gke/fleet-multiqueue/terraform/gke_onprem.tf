# On-premise Simulation GKE Cluster (Manager Cluster)
resource "google_container_cluster" "gke_onprem" {
  name                     = "gke-onprem-manager"
  location                 = var.region
  network                  = google_compute_network.vpc_onprem.name
  subnetwork               = google_compute_subnetwork.sub_onprem_gke.name
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  deletion_protection = false
  depends_on          = [time_sleep.wait_for_org_policy]
}

resource "google_container_node_pool" "onprem_nodes" {
  name       = "onprem-cpu-nodepool"
  location   = var.region
  cluster    = google_container_cluster.gke_onprem.name
  node_count = 2

  node_config {
    machine_type = "e2-standard-4"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    labels = {
      "node-role" = "onprem-manager"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}
