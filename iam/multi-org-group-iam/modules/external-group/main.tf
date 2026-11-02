# 1. 신규 조직 Cloud Identity에 그룹 생성 (Terraform SA 단독 Owner)
resource "google_cloud_identity_group" "this" {
  parent               = "customers/${var.customer_id}"
  display_name         = var.display_name
  description          = var.description
  initial_group_config = "WITH_INITIAL_OWNER"

  group_key {
    id = var.group_email
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }
}

# 2. 외부 도메인(@main-domain.com) 멤버 추가 허용 활성화 (Groups Settings API 1회 PATCH)
resource "terraform_data" "enable_external_members" {
  triggers_replace = [google_cloud_identity_group.this.id]

  provisioner "local-exec" {
    quiet = true
    environment = {
      SA_TOKEN    = var.sa_access_token
      GROUP_EMAIL = google_cloud_identity_group.this.group_key[0].id
    }
    command = <<-EOT
      resp=$(printf 'header = "Authorization: Bearer %s"\n' "$SA_TOKEN" \
        | curl -sS --fail-with-body --retry 8 --retry-delay 10 --retry-all-errors -K - \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d '{"allowExternalMembers": "true"}' \
            "https://www.googleapis.com/groups/v1/groups/$GROUP_EMAIL?alt=json") \
        || { printf '%s\n' "$resp" >&2; exit 1; }
    EOT
  }
}

# 3. 허용된 메인 로그인 도메인(@main-domain.com) 사용자를 그룹 멤버(MEMBER)로 등록
resource "google_cloud_identity_group_membership" "members" {
  for_each   = toset([for m in var.members : lower(trimspace(m))])
  depends_on = [terraform_data.enable_external_members]

  group = google_cloud_identity_group.this.id

  preferred_member_key {
    id = each.value
  }

  roles {
    name = "MEMBER"
  }
}
