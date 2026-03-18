#!/usr/bin/env bash
set -euo pipefail

# Smoke test toàn hệ thống (chức năng chính, khách quan)
# Chạy trên head01 với user có quyền SSH nội bộ + submit Slurm job.

HEAD_HOST="${HEAD_HOST:-head01}"
LOGIN_HOST="${LOGIN_HOST:-login01}"
STORAGE_HOST="${STORAGE_HOST:-storage01}"
COMPUTE_HOSTS_CSV="${COMPUTE_HOSTS:-compute01,compute02}"
LDAP_TEST_USER="${LDAP_TEST_USER:-hpc.test}"
LDAP_TEST_GROUP="${LDAP_TEST_GROUP:-g_stu}"
SLURM_PARTITION="${SLURM_PARTITION:-}"
SLURM_ACCOUNT="${SLURM_ACCOUNT:-}"
SLURM_CLUSTER_NAME="${SLURM_CLUSTER_NAME:-hpc-lab}"
CHECK_GUI="${CHECK_GUI:-1}"
SSH_STRICT_HOST_KEY_CHECKING="${SSH_STRICT_HOST_KEY_CHECKING:-accept-new}"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=${SSH_STRICT_HOST_KEY_CHECKING}"
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-120}"

IFS=',' read -r -a COMPUTE_HOSTS <<< "${COMPUTE_HOSTS_CSV}"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
  echo "PASS | $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "FAIL | $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
  echo "SKIP | $1"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

run_test() {
  local name="$1"
  shift

  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

is_local_host() {
  local host="$1"
  local hn_short hn_fqdn
  hn_short="$(hostname -s 2>/dev/null || true)"
  hn_fqdn="$(hostname -f 2>/dev/null || true)"

  [[ "${host}" == "localhost" ]] ||
  [[ "${host}" == "127.0.0.1" ]] ||
  [[ "${host}" == "${hn_short}" ]] ||
  [[ "${host}" == "${hn_fqdn}" ]]
}

run_host_cmd() {
  local host="$1"
  local cmd="$2"

  if is_local_host "${host}"; then
    bash -lc "${cmd}"
  else
    ssh ${SSH_OPTS} "${host}" "${cmd}"
  fi
}

resolve_slurm_partition() {
  if [[ -n "${SLURM_PARTITION}" ]]; then
    return 0
  fi

  if check_bin sinfo; then
    local detected
    detected="$(sinfo -h -o '%P' 2>/dev/null | awk '/\*/{gsub("\\*", "", $1); print $1; exit}')"
    if [[ -z "${detected}" ]]; then
      detected="$(sinfo -h -o '%P' 2>/dev/null | head -n1 | sed 's/\*//g' | xargs || true)"
    fi
    if [[ -n "${detected}" ]]; then
      SLURM_PARTITION="${detected}"
      return 0
    fi
  fi

  SLURM_PARTITION="small"
}

resolve_slurm_account() {
  if [[ -n "${SLURM_ACCOUNT}" ]]; then
    return 0
  fi

  if check_bin sacctmgr; then
    local detected
    detected="$(sacctmgr -nP show assoc user="$USER" format=Account 2>/dev/null | cut -d'|' -f1 | sed '/^$/d' | sort -u | head -n1 || true)"
    if [[ -n "${detected}" ]]; then
      SLURM_ACCOUNT="${detected}"
    fi
  fi
}

is_active_remote() {
  local host="$1"
  local service="$2"
  run_host_cmd "${host}" "systemctl is-active --quiet '${service}'"
}

check_bin() {
  command -v "$1" >/dev/null 2>&1
}

test_dns_resolution() {
  local host="$1"
  getent hosts "${host}" >/dev/null 2>&1
}

test_ssh_connectivity() {
  local host="$1"
  run_host_cmd "${host}" "echo ok" >/dev/null
}

test_ntp_synced() {
  local host="$1"
  run_host_cmd "${host}" "timedatectl show --property=NTPSynchronized --value | grep -Fxq yes"
}

test_identity_lookup() {
  run_host_cmd "${LOGIN_HOST}" "getent passwd '${LDAP_TEST_USER}'" >/dev/null
}

test_identity_group_lookup() {
  run_host_cmd "${LOGIN_HOST}" "getent group '${LDAP_TEST_GROUP}'" >/dev/null
}

test_nfs_mounts() {
  local mount_point
  for mount_point in /home /proj /soft; do
    run_host_cmd "${LOGIN_HOST}" "findmnt -n '${mount_point}'" >/dev/null || return 1
  done
}

test_nfs_exports() {
  run_host_cmd "${STORAGE_HOST}" "sudo exportfs -v | grep -Eq '^/home|^/proj|^/soft'"
}

test_slurm_nodes() {
  local output
  output="$(sinfo -N -h -o '%N|%t' 2>/dev/null || true)"
  [[ -n "${output}" ]] || return 1

  local host
  for host in "${COMPUTE_HOSTS[@]}"; do
    local state
    state="$(echo "${output}" | awk -F'|' -v h="${host}" '$1==h {print $2}' | head -n1)"
    [[ -n "${state}" ]] || return 1
    [[ "${state}" != *down* && "${state}" != *drain* && "${state}" != *fail* ]] || return 1
  done
}

test_slurm_cluster_registered() {
  check_bin sacctmgr || return 1
  sacctmgr -n list cluster 2>/dev/null | awk '{print $1}' | grep -Fxq "${SLURM_CLUSTER_NAME}"
}

test_slurm_default_accounts() {
  check_bin sacctmgr || return 1
  local accounts
  accounts="$(sacctmgr -n list account 2>/dev/null | awk '{print $1}')"
  echo "${accounts}" | grep -Fxq g_stu || return 1
  echo "${accounts}" | grep -Fxq g_lec || return 1
  echo "${accounts}" | grep -Fxq g_guest || return 1
}

test_slurmd_active_on_compute() {
  local host="$1"
  is_active_remote "${host}" "slurmd"
}

test_munge_active_on_compute() {
  local host="$1"
  is_active_remote "${host}" "munge"
}

test_slurm_submit_and_complete() {
  check_bin sbatch || return 1
  check_bin sacct || return 1

  local submit_cmd=(sbatch --parsable -p "${SLURM_PARTITION}")
  if [[ -n "${SLURM_ACCOUNT}" ]]; then
    submit_cmd+=( -A "${SLURM_ACCOUNT}" )
  fi
  submit_cmd+=(--wrap "hostname >/dev/null && sleep 1")

  local submit_out job_id
  submit_out="$("${submit_cmd[@]}" 2>/dev/null || true)"
  [[ -n "${submit_out}" ]] || return 1
  job_id="${submit_out%%;*}"
  [[ "${job_id}" =~ ^[0-9]+$ ]] || return 1

  local waited=0
  while (( waited < WAIT_TIMEOUT_SEC )); do
    local state
    state="$(sacct -j "${job_id}" --noheader --format=State 2>/dev/null | awk 'NF{print $1; exit}')"
    case "${state}" in
      COMPLETED) return 0 ;;
      FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY) return 1 ;;
      *) sleep 2; waited=$((waited + 2)) ;;
    esac
  done

  return 1
}

test_prometheus_health() {
  curl -fsS "http://${HEAD_HOST}:9090/-/healthy" | grep -qi "healthy"
}

test_grafana_health() {
  curl -fsS "http://${HEAD_HOST}:3000/api/health" | grep -qi '"database"\s*:\s*"ok"'
}

test_node_exporter_metrics() {
  curl -fsS -o /dev/null "http://${HEAD_HOST}:9100/metrics"
}

test_node_exporter_metrics_host() {
  local host="$1"
  curl -fsS -o /dev/null "http://${host}:9100/metrics"
}

test_login_gui_x2go() {
  run_host_cmd "${LOGIN_HOST}" "rpm -q x2goserver >/dev/null 2>&1" || return 1
  run_host_cmd "${LOGIN_HOST}" "systemctl list-unit-files | grep -q '^x2gocleansessions\.service'"
}

resolve_slurm_partition
resolve_slurm_account

echo "=== HPC System Smoke Test ==="
echo "HEAD_HOST=${HEAD_HOST} LOGIN_HOST=${LOGIN_HOST} STORAGE_HOST=${STORAGE_HOST}"
echo "COMPUTE_HOSTS=${COMPUTE_HOSTS_CSV} PARTITION=${SLURM_PARTITION}"
if [[ -n "${SLURM_ACCOUNT}" ]]; then
  echo "SLURM_ACCOUNT=${SLURM_ACCOUNT}"
fi
echo

for host in "${HEAD_HOST}" "${LOGIN_HOST}" "${STORAGE_HOST}" "${COMPUTE_HOSTS[@]}"; do
  run_test "DNS resolution: ${host}" test_dns_resolution "${host}"
done

for host in "${LOGIN_HOST}" "${STORAGE_HOST}" "${COMPUTE_HOSTS[@]}"; do
  run_test "SSH connectivity: ${host}" test_ssh_connectivity "${host}"
done

for host in "${HEAD_HOST}" "${LOGIN_HOST}" "${STORAGE_HOST}" "${COMPUTE_HOSTS[@]}"; do
  run_test "Time sync (NTP): ${host}" test_ntp_synced "${host}"
done

run_test "Identity: LDAP service active on ${HEAD_HOST}" is_active_remote "${HEAD_HOST}" "dirsrv@instance"
run_test "Identity: SSSD active on ${LOGIN_HOST}" is_active_remote "${LOGIN_HOST}" "sssd"
run_test "Identity: LDAP user lookup (${LDAP_TEST_USER}) from ${LOGIN_HOST}" test_identity_lookup
run_test "Identity: LDAP group lookup (${LDAP_TEST_GROUP}) from ${LOGIN_HOST}" test_identity_group_lookup

run_test "Storage: NFS server active on ${STORAGE_HOST}" is_active_remote "${STORAGE_HOST}" "nfs-server"
run_test "Storage: NFS exports include /home,/proj,/soft" test_nfs_exports
run_test "Storage: NFS mounts /home,/proj,/soft on ${LOGIN_HOST}" test_nfs_mounts

run_test "Slurm: munge active on ${HEAD_HOST}" is_active_remote "${HEAD_HOST}" "munge"
run_test "Slurm: slurmctld active on ${HEAD_HOST}" is_active_remote "${HEAD_HOST}" "slurmctld"
run_test "Slurm: slurmdbd active on ${HEAD_HOST}" is_active_remote "${HEAD_HOST}" "slurmdbd"
for host in "${COMPUTE_HOSTS[@]}"; do
  run_test "Slurm: munge active on ${host}" test_munge_active_on_compute "${host}"
  run_test "Slurm: slurmd active on ${host}" test_slurmd_active_on_compute "${host}"
done
run_test "Slurm: cluster registered (${SLURM_CLUSTER_NAME})" test_slurm_cluster_registered
run_test "Slurm: default accounts exist (g_stu,g_lec,g_guest)" test_slurm_default_accounts
run_test "Slurm: compute nodes state healthy" test_slurm_nodes
run_test "Slurm: submit and complete one short job" test_slurm_submit_and_complete

run_test "Monitoring: Prometheus health endpoint" test_prometheus_health
run_test "Monitoring: Grafana health endpoint" test_grafana_health
run_test "Monitoring: Node exporter metrics endpoint" test_node_exporter_metrics
for host in "${LOGIN_HOST}" "${STORAGE_HOST}" "${COMPUTE_HOSTS[@]}"; do
  run_test "Monitoring: node_exporter metrics on ${host}" test_node_exporter_metrics_host "${host}"
done

if [[ "${CHECK_GUI}" == "1" ]]; then
  if test_login_gui_x2go; then
    pass "Login GUI: x2goserver installed on ${LOGIN_HOST}"
  else
    skip "Login GUI: x2goserver not detected on ${LOGIN_HOST}"
  fi
else
  skip "Login GUI checks disabled (CHECK_GUI=${CHECK_GUI})"
fi

echo
echo "=== Summary ==="
echo "PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT}"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
