# ==============================================================================
# Organization Policy Deployment Engine
# ==============================================================================

locals {
  # policy_scope = "organization" 이면 Organization 루트(organizations/<org_id>),
  # policy_scope = "folder" 이면 지정된 target_folder_id 또는 자동 생성된 실습 폴더(folders/<id>)에 정책을 부착합니다.
  policy_parent = (
    var.policy_scope == "organization"
    ? "organizations/${var.org_id}"
    : (
      var.target_folder_id != ""
      ? "folders/${var.target_folder_id}"
      : google_folder.handson_lab[0].name
    )
  )

  # 최종 유효 모드가 "UNMANAGED"가 아닌 정책만 필터링하여 리소스 생성
  active_policies = {
    for constraint, cfg in local.policy_catalog :
    constraint => merge(cfg, {
      mode = local.effective_policy_modes[constraint]
    })
    if local.effective_policy_modes[constraint] != "UNMANAGED"
  }
}

resource "google_org_policy_policy" "policy" {
  for_each = local.active_policies

  name   = "${local.policy_parent}/policies/${each.key}"
  parent = local.policy_parent

  # ENFORCED 모드일 때 실제 강제 규칙(spec) 적용
  dynamic "spec" {
    for_each = each.value.mode == "ENFORCED" ? [1] : []
    content {
      inherit_from_parent = each.value.inherit_from_parent

      dynamic "rules" {
        for_each = each.value.rules
        content {
          dynamic "condition" {
            for_each = rules.value.condition != null ? [rules.value.condition] : []
            content {
              title       = condition.value.title
              description = condition.value.description
              expression  = condition.value.expression
            }
          }

          enforce    = rules.value.enforce
          allow_all  = rules.value.allow_all
          deny_all   = rules.value.deny_all
          parameters = rules.value.parameters

          dynamic "values" {
            for_each = rules.value.allowed_values != null ? [rules.value.allowed_values] : []
            content {
              allowed_values = values.value
            }
          }
        }
      }
    }
  }

  # DRY_RUN 모드일 때 차단 없이 감사 로그만 남기는 규칙(dry_run_spec) 적용
  dynamic "dry_run_spec" {
    for_each = each.value.mode == "DRY_RUN" ? [1] : []
    content {
      inherit_from_parent = each.value.inherit_from_parent

      dynamic "rules" {
        for_each = each.value.rules
        content {
          dynamic "condition" {
            for_each = rules.value.condition != null ? [rules.value.condition] : []
            content {
              title       = "${condition.value.title} (Dry-Run)"
              description = condition.value.description
              expression  = condition.value.expression
            }
          }

          enforce    = rules.value.enforce
          allow_all  = rules.value.allow_all
          deny_all   = rules.value.deny_all
          parameters = rules.value.parameters

          dynamic "values" {
            for_each = rules.value.allowed_values != null ? [rules.value.allowed_values] : []
            content {
              allowed_values = values.value
            }
          }
        }
      }
    }
  }
}
