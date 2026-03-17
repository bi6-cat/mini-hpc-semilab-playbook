# Manual Slurm Tests (run from login node)

Mục tiêu: cho user tự chạy tay trên `login01` giống workflow thực tế.

## 1) Copy folder lên login node (nếu cần)

```bash
scp -r scripts/manual-login-tests <user>@login01.lab.local:~/
```

Hoặc nếu đang đứng tại `login01`, chỉ cần:

```bash
cd ~/manual-login-tests
```

## 2) Submit các bài test

Mặc định script để `-A g_stu -p small`. Nếu user thuộc account khác, override khi submit.

```bash
mkdir -p logs

# Queue test (array)
sbatch -A g_stu -p small 01-queue-array.sbatch

# Multi task test
sbatch -A g_stu -p small 02-multi-task.sbatch

# CPU heavy
sbatch -A g_stu -p small 03-cpu-heavy.sbatch

# Memory heavy
sbatch -A g_stu -p small 04-mem-heavy.sbatch

# IO heavy
sbatch -A g_stu -p small 05-io-heavy.sbatch
```

Ví dụ cho giảng viên:

```bash
sbatch -A g_lec -p small 03-cpu-heavy.sbatch
```

### Chạy tất cả bằng 1 lệnh

```bash
chmod +x run-all.sh
./run-all.sh g_stu small
```

Cho giảng viên:

```bash
./run-all.sh g_lec small
```

## 3) Theo dõi kết quả

```bash
squeue -u $USER
sacct -u $USER --format=JobID,JobName,Partition,Account,State,Elapsed,ExitCode
ls -lah logs/
```
