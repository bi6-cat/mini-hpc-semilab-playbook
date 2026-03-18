#!/bin/bash
#SBATCH -J multi_manual
#SBATCH -p small
#SBATCH -A g_stu
#SBATCH -N 1
#SBATCH -n 4
#SBATCH -c 1
#SBATCH --mem=1G
#SBATCH -t 00:05:00
#SBATCH -o logs/multi-%j.out

set -euo pipefail
srun -n 4 bash -lc 'echo "MULTI rank=$SLURM_PROCID host=$(hostname) user=$USER"; sleep 10'
