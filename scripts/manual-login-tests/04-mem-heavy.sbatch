#!/bin/bash
#SBATCH -J mem_manual
#SBATCH -p small
#SBATCH -A g_stu
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
#SBATCH --mem=8G
#SBATCH -t 00:10:00
#SBATCH -o logs/mem-%j.out

set -euo pipefail
python3 - <<'PY'
import time
blocks = []
for _ in range(8):
    blocks.append(bytearray(512 * 1024 * 1024))
    time.sleep(0.3)
print("MEM_OK", len(blocks))
PY
