#!/bin/bash
#SBATCH -J io_manual
#SBATCH -p regular
#SBATCH -A stu
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 2
#SBATCH --mem=2G
#SBATCH -t 00:10:00
#SBATCH -o logs/io-%j.out

set -euo pipefail
if command -v fio >/dev/null 2>&1; then
  fio --name=rwtest --directory=/tmp --size=2G --bs=1M --rw=readwrite --direct=1 --iodepth=16 --numjobs=1 --runtime=40 --time_based=1
else
  dd if=/dev/zero of=/tmp/slurm-io-manual.bin bs=1M count=2048 conv=fdatasync
  dd if=/tmp/slurm-io-manual.bin of=/dev/null bs=1M
  rm -f /tmp/slurm-io-manual.bin
fi
