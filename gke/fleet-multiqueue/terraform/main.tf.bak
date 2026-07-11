terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "gke-fleet-multiq"
}

variable "region" {
  description = "Primary GCP Region"
  type        = string
  default     = "asia-northeast1"
}

variable "enable_cloud_dns" {
  description = "Enable Cloud DNS API"
  type        = bool
  default     = false
}

provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

# ────────────────────────────────────────────────────────────────────
# 1. 필수 Google Cloud API 서비스 활성화
# ────────────────────────────────────────────────────────────────────
locals {
  required_apis = compact([
    "cloudresourcemanager.googleapis.com",              # Cloud Resource Manager API
    "compute.googleapis.com",                           # Compute Engine API
    "container.googleapis.com",                         # Kubernetes Engine API
    "gkehub.googleapis.com",                            # GKE Fleet Hub API
    "connectgateway.googleapis.com",                    # Connect Gateway API
    "orgpolicy.googleapis.com",                         # Organization Policy API
    var.enable_cloud_dns ? "dns.googleapis.com" : null, # Cloud DNS API (선택사항)
  ])
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ────────────────────────────────────────────────────────────────────
# 2. 조직 정책 (Organization Policy) 해제
# ────────────────────────────────────────────────────────────────────
# 인터넷 NEG 생성 제한 해제
resource "google_org_policy_policy" "disable_internet_neg" {
  name   = "projects/${var.project_id}/policies/compute.disableInternetNetworkEndpointGroup"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "FALSE"
    }
  }

  depends_on = [google_project_service.apis]
}

# 로드밸런서 타입 제한 해제
resource "google_org_policy_policy" "allow_lb_types" {
  name   = "projects/${var.project_id}/policies/compute.restrictLoadBalancerCreationForTypes"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      allow_all = "TRUE"
    }
  }

  depends_on = [google_project_service.apis]
}

# VPN Peer IP 제한 (restrictVpnPeerIPs) 해제
resource "google_org_policy_policy" "allow_vpn_peer_ips" {
  name   = "projects/${var.project_id}/policies/compute.restrictVpnPeerIPs"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      allow_all = "TRUE"
    }
  }

  depends_on = [google_project_service.apis]
}

# Shielded VM 의무화 (requireShieldedVm) 해제
resource "google_org_policy_policy" "disable_shielded_vm" {
  name   = "projects/${var.project_id}/policies/compute.requireShieldedVm"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "FALSE"
    }
  }

  depends_on = [google_project_service.apis]
}

# 조직 정책 변경 사항이 GCP Compute Engine API 전파 캐시에 반영되도록 60초간 대기합니다.
resource "time_sleep" "wait_for_org_policy" {
  create_duration = "60s"

  triggers = {
    allow_lb_types       = google_org_policy_policy.allow_lb_types.id
    disable_internet_neg = google_org_policy_policy.disable_internet_neg.id
    allow_vpn_peer_ips   = google_org_policy_policy.allow_vpn_peer_ips.id
    disable_shielded_vm  = google_org_policy_policy.disable_shielded_vm.id
  }

  depends_on = [
    google_org_policy_policy.disable_internet_neg,
    google_org_policy_policy.allow_lb_types,
    google_org_policy_policy.allow_vpn_peer_ips,
    google_org_policy_policy.disable_shielded_vm
  ]
}
