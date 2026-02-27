#!/bin/bash
#SBATCH -J qburst_manual
#SBATCH -p regular
#SBATCH -A stu
#SBATCH --array=1-12%3
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 1
#SBATCH --mem=256M
#SBATCH -t 00:05:00
#SBATCH -o logs/queue-%A_%a.out

set -euo pipefail
echo "QUEUE task=${SLURM_ARRAY_TASK_ID} user=${USER} host=$(hostname)"
sleep 15
