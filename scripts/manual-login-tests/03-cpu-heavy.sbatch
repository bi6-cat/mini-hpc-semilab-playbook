#!/bin/bash
#SBATCH -J cpu_manual
#SBATCH -p regular
#SBATCH -A stu
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 8
#SBATCH --mem=4G
#SBATCH -t 00:10:00
#SBATCH -o logs/cpu-%j.out

set -euo pipefail
echo "CPU test on $(hostname), cpus=${SLURM_CPUS_PER_TASK:-1}"
openssl speed -seconds 45 -multi "${SLURM_CPUS_PER_TASK:-4}" sha256
