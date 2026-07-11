# HA VPN Gateways
resource "google_compute_ha_vpn_gateway" "vpn_onprem" {
  name       = "vpn-gw-onprem"
  network    = google_compute_network.vpc_onprem.id
  region     = var.region
  depends_on = [time_sleep.wait_for_org_policy]
}

resource "google_compute_ha_vpn_gateway" "vpn_cloud" {
  name       = "vpn-gw-cloud"
  network    = google_compute_network.vpc_cloud.id
  region     = var.region
  depends_on = [time_sleep.wait_for_org_policy]
}

# Cloud Routers for BGP
resource "google_compute_router" "router_onprem" {
  name    = "router-onprem"
  network = google_compute_network.vpc_onprem.name
  region  = var.region
  bgp {
    asn = 65001
  }
}

resource "google_compute_router" "router_cloud" {
  name    = "router-cloud"
  network = google_compute_network.vpc_cloud.name
  region  = var.region
  bgp {
    asn = 65002
  }
}

# Shared Secret for IPsec
resource "random_id" "vpn_secret" {
  byte_length = 16
}

# VPN Tunnels (Tunnel 0 & Tunnel 1)
resource "google_compute_vpn_tunnel" "tunnel_onprem_to_cloud_0" {
  name                  = "tunnel-onprem-to-cloud-0"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.vpn_onprem.id
  vpn_gateway_interface = 0
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.vpn_cloud.id
  shared_secret         = random_id.vpn_secret.b64_url
  router                = google_compute_router.router_onprem.name
  depends_on            = [time_sleep.wait_for_org_policy]
}

resource "google_compute_vpn_tunnel" "tunnel_cloud_to_onprem_0" {
  name                  = "tunnel-cloud-to-onprem-0"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.vpn_cloud.id
  vpn_gateway_interface = 0
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.vpn_onprem.id
  shared_secret         = random_id.vpn_secret.b64_url
  router                = google_compute_router.router_cloud.name
  depends_on            = [time_sleep.wait_for_org_policy]
}

# BGP Interfaces and Peers
resource "google_compute_router_interface" "if_onprem_0" {
  name       = "if-onprem-0"
  router     = google_compute_router.router_onprem.name
  region     = var.region
  ip_range   = "169.254.0.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel_onprem_to_cloud_0.name
}

resource "google_compute_router_peer" "peer_onprem_0" {
  name                      = "peer-onprem-0"
  router                    = google_compute_router.router_onprem.name
  region                    = var.region
  peer_ip_address           = "169.254.0.2"
  peer_asn                  = 65002
  interface                 = google_compute_router_interface.if_onprem_0.name
  router_appliance_instance = null
}

resource "google_compute_router_interface" "if_cloud_0" {
  name       = "if-cloud-0"
  router     = google_compute_router.router_cloud.name
  region     = var.region
  ip_range   = "169.254.0.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel_cloud_to_onprem_0.name
}

resource "google_compute_router_peer" "peer_cloud_0" {
  name                      = "peer-cloud-0"
  router                    = google_compute_router.router_cloud.name
  region                    = var.region
  peer_ip_address           = "169.254.0.1"
  peer_asn                  = 65001
  interface                 = google_compute_router_interface.if_cloud_0.name
  router_appliance_instance = null
}
