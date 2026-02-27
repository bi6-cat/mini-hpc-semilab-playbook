#!/usr/bin/env bash
set -euo pipefail

ACCOUNT="${1:-stu}"
PARTITION="${2:-regular}"

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

for script in "${SCRIPTS[@]}"; do
  if [[ ! -f "$script" ]]; then
    echo "Skip missing file: $script"
    continue
  fi

  job_id="$(sbatch --parsable -A "$ACCOUNT" -p "$PARTITION" "$script" | cut -d';' -f1)"
  echo "$script -> job_id=$job_id"
done

echo "Done. Check queue: squeue -u $USER"
echo "Check history: sacct -u $USER --format=JobID,JobName,Partition,Account,State,Elapsed,ExitCode"
