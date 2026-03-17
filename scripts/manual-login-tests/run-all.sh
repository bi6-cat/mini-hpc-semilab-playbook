#!/usr/bin/env bash
set -euo pipefail

ACCOUNT="${1:-g_stu}"
PARTITION="${2:-small}"

SCRIPTS=(
  "01-queue-array.sbatch"
  "02-multi-task.sbatch"
  "03-cpu-heavy.sbatch"
  "04-mem-heavy.sbatch"
  "05-io-heavy.sbatch"
)

mkdir -p logs

echo "Submit all manual Slurm tests"
echo "account=${ACCOUNT} partition=${PARTITION} user=${USER}"

if command -v sinfo >/dev/null 2>&1; then
  if ! sinfo -h -o "%P" | sed 's/*//g' | tr -d ' ' | grep -Fxq "$PARTITION"; then
    echo "ERROR: partition '${PARTITION}' does not exist"
    echo "Available partitions:"
    sinfo -h -o "%P" | sed 's/*//g' | xargs -n1 echo "-"
    exit 1
  fi
fi

if command -v sacctmgr >/dev/null 2>&1; then
  if ! sacctmgr -nP show assoc user="$USER" format=Account 2>/dev/null | cut -d'|' -f1 | grep -Fxq "$ACCOUNT"; then
    echo "ERROR: account '${ACCOUNT}' is not associated with user '${USER}'"
    echo "Your available accounts:"
    sacctmgr -nP show assoc user="$USER" format=Account 2>/dev/null | cut -d'|' -f1 | sort -u | sed '/^$/d' | xargs -n1 echo "-"
    exit 1
  fi
fi

for script in "${SCRIPTS[@]}"; do
  if [[ ! -f "$script" ]]; then
    echo "Skip missing file: $script"
    continue
  fi

  extra_args=()
  if [[ "$script" == "03-cpu-heavy.sbatch" && "$PARTITION" == "tiny" ]]; then
    # tiny is intended for small jobs; cap CPU request to 4 when submitting this workload.
    extra_args+=(--cpus-per-task=4)
  fi

  job_id="$(sbatch --parsable -A "$ACCOUNT" -p "$PARTITION" "${extra_args[@]}" "$script" | cut -d';' -f1)"
  echo "$script -> job_id=$job_id"
done

echo "Done. Check queue: squeue -u $USER"
echo "Check history: sacct -u $USER --format=JobID,JobName,Partition,Account,State,Elapsed,ExitCode"
