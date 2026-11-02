# ==============================================================================
# Organization Policy Mode Resolution & Deployment Engine
# ==============================================================================

locals {
  # 1. 정책 부착 상위 리소스 경로 (Organization 루트 vs 격리 실습/지정 폴더)
  policy_parent = (
    var.policy_scope == "organization" ? "organizations/${var.org_id}" :
    var.target_folder_id != "" ? "folders/${var.target_folder_id}" :
    google_folder.handson_lab[0].name
  )

  # 2. 티어별 기본 모드 매핑
  tier_default_modes = {
    baseline    = var.baseline_policy_mode
    audit_first = var.audit_first_policy_mode
    opt_in      = var.opt_in_policy_mode
    migration   = "ENFORCED"
  }

  # 3. 각 정책의 최종 유효 모드 계산 ("ENFORCED" | "DRY_RUN" | "UNMANAGED")
  #    - enabled 조건이 false이면 UNMANAGED 처리
  #    - 그렇지 않으면 policy_mode_overrides 개별 설정을 우선 적용하고, 없으면 티어 기본값 적용
  effective_policy_modes = {
    for constraint, cfg in local.policy_catalog :
    constraint => (
      try(cfg.enabled, true)
      ? lookup(var.policy_mode_overrides, constraint, local.tier_default_modes[cfg.tier])
      : "UNMANAGED"
    )
  }

  # 4. 실제 생성·관리할 정책만 필터링하고 생략된 선택 속성(null)을 정규화
  active_policies = {
    for constraint, cfg in local.policy_catalog :
    constraint => {
      mode                = local.effective_policy_modes[constraint]
      inherit_from_parent = try(cfg.inherit_from_parent, null)
      rules = [
        for r in cfg.rules : {
          condition      = try(r.condition, null)
          enforce        = try(r.enforce, null)
          allow_all      = try(r.allow_all, null)
          deny_all       = try(r.deny_all, null)
          parameters     = try(r.parameters, null)
          allowed_values = try(r.allowed_values, null)
        }
      ]
    }
    if local.effective_policy_modes[constraint] != "UNMANAGED"
  }
}

resource "google_org_policy_policy" "policy" {
  for_each = local.active_policies

  name   = "${local.policy_parent}/policies/${each.key}"
  parent = local.policy_parent

  # ENFORCED 모드: 실제 차단/허용 규칙(spec) 적용
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

  # DRY_RUN 모드: 워크로드 차단 없이 감사 로그만 기록하는 규칙(dry_run_spec) 적용
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
