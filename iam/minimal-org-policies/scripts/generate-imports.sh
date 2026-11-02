#!/usr/bin/env bash
# ==============================================================================
# generate-imports.sh
# ------------------------------------------------------------------------------
# 신규 생성되거나 운영 중인 GCP Organization(또는 기존 Folder)에는 Google의
# Secure-by-Default 기본 보안 정책들이 이미 생성되어 있는 경우가 많습니다.
# 본 스크립트는 대상 범위의 기존 정책(JSON)과 로컬 *.tf 정적 리소스 선언을 대조하여:
#   1) 활성화된 google_org_policy_policy 리소스와 매칭되는 `imports.tf` 블록 자동 생성
#   2) 이미 GCP에서 ENFORCED(spec 활성) 중인 정책이 dry_run_spec으로 강등될 위험 자동 감지 및 안내
#   3) .managed. 정책과 중복 평가될 수 있는 레거시 기본 정책 존재 여부 감지 및 안내
# 를 수행합니다.
#
# 사용 예시:
#   ./scripts/generate-imports.sh --org 123456789012
#   ./scripts/generate-imports.sh --folder 9876543210
#   ./scripts/generate-imports.sh --org 123456789012 \
#     --impersonate-sa tf-iam-admin@iam-seed-prod-01.iam.gserviceaccount.com \
#     --billing-project iam-seed-prod-01
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_FILE="${ROOT_DIR}/imports.tf"

SCOPE_FLAG=""
SCOPE_ID=""
PARENT_PATH=""
IMPERSONATE_SA=""
BILLING_PROJECT=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/generate-imports.sh (--org <ORG_ID> | --folder <FOLDER_ID>) [options]

Options:
  --org <ORG_ID>                  대상 GCP Organization 숫자형 ID
  --folder <FOLDER_ID>            대상 GCP Folder 숫자형 ID
  --impersonate-sa <SA_EMAIL>     (선택) Keyless SA Impersonation 이메일
  --billing-project <PROJECT_ID>  (선택) API 쿼터 프로젝트 ID
  -h, --help                      도움말 출력
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      SCOPE_FLAG="--organization"
      SCOPE_ID="$2"
      PARENT_PATH="organizations/$2"
      shift 2
      ;;
    --folder)
      SCOPE_FLAG="--folder"
      SCOPE_ID="$2"
      PARENT_PATH="folders/$2"
      shift 2
      ;;
    --impersonate-sa)
      IMPERSONATE_SA="$2"
      shift 2
      ;;
    --billing-project)
      BILLING_PROJECT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${SCOPE_FLAG}" || -z "${SCOPE_ID}" ]]; then
  echo "[ERROR] --org <ORG_ID> 또는 --folder <FOLDER_ID> 중 하나를 반드시 지정해야 합니다." >&2
  usage >&2
  exit 1
fi

GCLOUD_ARGS=("${SCOPE_FLAG}=${SCOPE_ID}" "--format=json")
if [[ -n "${IMPERSONATE_SA}" ]]; then
  GCLOUD_ARGS+=("--impersonate-service-account=${IMPERSONATE_SA}")
fi
if [[ -n "${BILLING_PROJECT}" ]]; then
  GCLOUD_ARGS+=("--billing-project=${BILLING_PROJECT}")
fi

echo "==> [1/2] ${PARENT_PATH} 에 현재 존재하는 Organization Policy 목록 및 강제 상태를 조회합니다..."
EXISTING_JSON="$(gcloud org-policies list "${GCLOUD_ARGS[@]}")"

echo "==> [2/2] 로컬 *.tf 정적 정책 선언과 대조하여 ${OUTPUT_FILE} 파일을 생성합니다..."
python3 - "${EXISTING_JSON}" "${ROOT_DIR}" "${PARENT_PATH}" "${OUTPUT_FILE}" <<'PYEOF'
import glob
import json
import os
import re
import sys

existing_raw, root_dir, parent_path, output_file = sys.argv[1:5]

def strip_hcl_comments(text: str) -> str:
    # Remove /* ... */ block comments first, then # / // line comments
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    cleaned_lines = []
    for line in text.splitlines():
        s = line.lstrip()
        if s.startswith("#") or s.startswith("//"):
            continue
        cleaned_lines.append(line)
    return "\n".join(cleaned_lines)

def check_tfvars_nonempty_list(tfvars_text: str, var_name: str) -> bool:
    m = re.search(rf"\b{re.escape(var_name)}\s*=\s*\[(.*?)\]", tfvars_text, flags=re.DOTALL)
    if not m:
        return False
    inner = strip_hcl_comments(m.group(1)).strip()
    return len(inner) > 0

tfvars_path = os.path.join(root_dir, "terraform.tfvars")
tfvars_text = ""
if os.path.exists(tfvars_path):
    with open(tfvars_path, encoding="utf-8") as f:
        tfvars_text = f.read()

# Parse active google_org_policy_policy resources from *.tf files
declared_policies: dict[str, dict] = {}
all_known_constraints: set[str] = set()

for tf_path in sorted(glob.glob(os.path.join(root_dir, "*.tf"))):
    fname = os.path.basename(tf_path)
    if fname == "imports.tf":
        continue
    with open(tf_path, encoding="utf-8") as f:
        raw_tf = f.read()

    # Collect all constraint names (even commented-out ones in opt_in_policies.tf)
    for cm in re.finditer(r"/policies/([A-Za-z0-9_.]+)", raw_tf):
        all_known_constraints.add(cm.group(1))

    active_tf = strip_hcl_comments(raw_tf)
    pos = 0
    header_re = re.compile(r'resource\s+"google_org_policy_policy"\s+"([A-Za-z0-9_]+)"\s*\{')
    while True:
        m = header_re.search(active_tf, pos)
        if not m:
            break
        tf_name = m.group(1)
        brace_start = m.end() - 1
        depth = 0
        end_idx = brace_start
        for i in range(brace_start, len(active_tf)):
            if active_tf[i] == "{":
                depth += 1
            elif active_tf[i] == "}":
                depth -= 1
                if depth == 0:
                    end_idx = i + 1
                    break
        body = active_tf[brace_start:end_idx]
        pos = end_idx

        cm = re.search(r"/policies/([A-Za-z0-9_.]+)", body)
        if not cm:
            continue
        constraint = cm.group(1)

        has_count = re.search(r"^\s*count\s*=", body, flags=re.MULTILINE) is not None
        if has_count:
            var_m = re.search(r"var\.([A-Za-z0-9_]+)", body)
            if var_m and not check_tfvars_nonempty_list(tfvars_text, var_m.group(1)):
                continue
            tf_addr = f"google_org_policy_policy.{tf_name}[0]"
        else:
            tf_addr = f"google_org_policy_policy.{tf_name}"

        mode = "DRY_RUN" if re.search(r"\bdry_run_spec\s*\{", body) else "ENFORCED"
        declared_policies[constraint] = {
            "tf_name": tf_name,
            "tf_addr": tf_addr,
            "mode": mode,
            "file": fname,
        }

def is_live_spec_enforced(policy_obj: dict) -> bool:
    spec = policy_obj.get("spec") or {}
    if spec.get("reset") is True:
        return False
    rules = spec.get("rules") or []
    if not rules:
        return False
    for r in rules:
        if "condition" in r:
            continue
        if r.get("enforce") is True:
            return True
        if r.get("denyAll") is True:
            return True
        if "values" in r or "parameters" in r:
            if r.get("enforce") is not False and r.get("allowAll") is not True:
                return True
    return False

existing_list = json.loads(existing_raw) if existing_raw.strip() else []
existing_by_constraint: dict[str, dict] = {}
for item in existing_list:
    name = item.get("name", "")
    if "/policies/" in name:
        constraint = name.split("/policies/", 1)[1]
        existing_by_constraint[constraint] = item

existing_constraints = sorted(existing_by_constraint.keys())
to_import = [c for c in existing_constraints if c in declared_policies]
commented_existing = [c for c in existing_constraints if c in all_known_constraints and c not in declared_policies]

downgraded_from_enforced = [
    c for c in to_import
    if declared_policies[c]["mode"] == "DRY_RUN" and is_live_spec_enforced(existing_by_constraint[c])
]

legacy_counterparts = {
    "iam.allowedPolicyMemberDomains": "iam.managed.allowedPolicyMembers",
    "iam.disableServiceAccountKeyCreation": "iam.managed.disableServiceAccountKeyCreation",
    "iam.disableServiceAccountKeyUpload": "iam.managed.disableServiceAccountKeyUpload",
    "compute.disableSerialPortAccess": "compute.managed.disableSerialPortAccess",
    "compute.disableNestedVirtualization": "compute.managed.disableNestedVirtualization",
    "compute.requireOsLogin": "compute.managed.requireOsLogin",
    "compute.trustedImageProjects": "compute.managed.trustedImageProjects",
    "compute.restrictProtocolForwardingCreationForTypes": "compute.managed.restrictProtocolForwardingCreationForTypes",
    "compute.vmExternalIpAccess": "compute.managed.vmExternalIpAccess",
    "sql.restrictPublicIp": "sql.managed.restrictPublicIp",
    "sql.restrictAuthorizedNetworks": "sql.managed.restrictAuthorizedNetworks",
}
detected_legacy = [
    (leg, legacy_counterparts[leg])
    for leg in existing_constraints
    if leg in legacy_counterparts
]

lines = [
    "# Auto-generated by scripts/generate-imports.sh",
    f"# Target parent: {parent_path}",
    "# Note: This file is gitignored. You may keep or delete it after 'terraform apply' succeeds.",
    "",
]

for c in to_import:
    info = declared_policies[c]
    lines.extend([
        "import {",
        f"  to = {info['tf_addr']}",
        f'  id = "{parent_path}/policies/{c}"',
        "}",
        "",
    ])

with open(output_file, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print(f"\n[완료] 총 {len(to_import)}개의 기존 정책에 대한 import 블록을 '{output_file}'에 생성했습니다.")
for c in to_import:
    info = declared_policies[c]
    print(f"  + import: {info['tf_addr']} <- {parent_path}/policies/{c} ({info['file']}: {info['mode']})")

if downgraded_from_enforced:
    print("\n================================================================================")
    print("[보안 경고] 이미 GCP에서 ENFORCED(강제) 중인 정책이 코드에서는 'dry_run_spec'(감사 모드)으로 선언되어 있습니다!")
    print("2024년 5월 이후 생성된 신규 Org의 Secure-by-Default 정책 등이 여기에 해당합니다.")
    print("그대로 apply 하면 기존 강제(spec)가 해제되고 감사 전용(dry_run_spec)으로 완화됩니다.")
    print("기존 강제를 유지하면서 태그 예외 규칙만 추가하려면 아래 리소스 블록의 'dry_run_spec'을 'spec'으로 변경하세요:")
    print("")
    for c in downgraded_from_enforced:
        info = declared_policies[c]
        print(f"  - {info['file']} -> resource \"google_org_policy_policy\" \"{info['tf_name']}\" ({c})")
    print("================================================================================")

if commented_existing:
    print("\n[참고] 아래 정책은 현재 GCP에 이미 설정되어 있으나 opt_in_policies.tf (또는 조건부 설정)에서 비활성 상태입니다.")
    print("       Terraform은 해당 정책을 건드리지 않고 현재 GCP 상태를 그대로 유지합니다.")
    print("       코드로 함께 관리하려면 opt_in_policies.tf에서 해당 주석을 해제한 뒤 본 스크립트를 다시 실행하세요:")
    for c in commented_existing:
        print(f"  - {c}")

if detected_legacy:
    print("\n[주의] 대상 범위에서 Google-Managed(.managed.) 정책과 중복 평가될 수 있는 레거시 기본 정책이 감지되었습니다:")
    for leg, mgd in detected_legacy:
        print(f"  ! 레거시 '{leg}' 감지됨 (본 코드는 차세대 '{mgd}' 사용)")
    print("       레거시 정책과 .managed. 정책은 독립 평가되므로, 레거시 정책에 태그 예외가 없다면 의도치 않은 차단이 발생할 수 있습니다.")
    print("       필요 시 'gcloud org-policies describe <LEGACY_CONSTRAINT> ...' 로 확인 후 정리(delete/reset)를 검토하세요.")
PYEOF
