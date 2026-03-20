#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${INVENTORY:-inventory/dev/hosts.yml}"
SMOKE_SCRIPT="${SMOKE_SCRIPT:-scripts/system-smoke-test.sh}"
ANSIBLE_BIN="${ANSIBLE_BIN:-ansible-playbook}"
RUN_SMOKE_TEST="${RUN_SMOKE_TEST:-1}"
ANSIBLE_ADHOC_BIN="${ANSIBLE_ADHOC_BIN:-ansible}"

PLAYBOOKS=(
  "00-bootstrap.yml"
  "01-identity.yml"
  "02-storage.yml"
  "03-login-gui.yml"
  "04-slurm-head.yml"
  "05-slurm-compute.yml"
  "06-monitoring.yml"
)

VAULT_ARGS=()
VAULT_TMP_FILE=""

cleanup() {
  if [[ -n "${VAULT_TMP_FILE}" && -f "${VAULT_TMP_FILE}" ]]; then
    rm -f "${VAULT_TMP_FILE}"
  fi
}
trap cleanup EXIT

log() {
  echo "[$(date +'%F %T')] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 127
  }
}

setup_vault_args() {
  if [[ -n "${VAULT_PASSWORD_FILE:-}" ]]; then
    if [[ ! -f "${VAULT_PASSWORD_FILE}" ]]; then
      echo "VAULT_PASSWORD_FILE not found: ${VAULT_PASSWORD_FILE}" >&2
      exit 1
    fi
    VAULT_ARGS=(--vault-password-file "${VAULT_PASSWORD_FILE}")
    return
  fi

  if [[ "${NO_VAULT:-0}" == "1" ]]; then
    VAULT_ARGS=()
    return
  fi

  local vault_password=""
  read -r -s -p "Vault password: " vault_password
  echo

  VAULT_TMP_FILE="$(mktemp)"
  chmod 600 "${VAULT_TMP_FILE}"
  printf '%s' "${vault_password}" > "${VAULT_TMP_FILE}"
  unset vault_password

  VAULT_ARGS=(--vault-password-file "${VAULT_TMP_FILE}")
}

run_playbook() {
  local playbook="$1"
  log "Running ${playbook}"
  "${ANSIBLE_BIN}" -i "${INVENTORY}" "playbooks/${playbook}" "${VAULT_ARGS[@]}"
}

main() {
  cd "${ROOT_DIR}"

  require_cmd "${ANSIBLE_BIN}"
  require_cmd "${ANSIBLE_ADHOC_BIN}"
  require_cmd "bash"

  if [[ ! -f "${INVENTORY}" ]]; then
    echo "Inventory file not found: ${INVENTORY}" >&2
    exit 1
  fi

  if [[ ! -f "${SMOKE_SCRIPT}" ]]; then
    echo "Smoke test script not found: ${SMOKE_SCRIPT}" >&2
    exit 1
  fi

  setup_vault_args

  log "Start full deployment (each playbook runs 2 times)"
  for pass in 1 2; do
    log "=== Pass ${pass}/2 ==="
    for playbook in "${PLAYBOOKS[@]}"; do
      run_playbook "${playbook}"
    done
  done

  if [[ "${RUN_SMOKE_TEST}" == "1" ]]; then
    log "Running smoke test: ${SMOKE_SCRIPT}"
    bash "${SMOKE_SCRIPT}"
  else
    log "Smoke test skipped (RUN_SMOKE_TEST=${RUN_SMOKE_TEST})"
  fi

  log "Completed successfully"
}

main "$@"
