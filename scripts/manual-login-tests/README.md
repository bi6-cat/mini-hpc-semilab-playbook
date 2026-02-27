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

Mặc định script để `-A stu -p regular`. Nếu user thuộc account khác, override khi submit.

```bash
mkdir -p logs

# Queue test (array)
sbatch -A stu -p regular 01-queue-array.sbatch

# Multi task test
sbatch -A stu -p regular 02-multi-task.sbatch

# CPU heavy
sbatch -A stu -p regular 03-cpu-heavy.sbatch

# Memory heavy
sbatch -A stu -p regular 04-mem-heavy.sbatch

# IO heavy
sbatch -A stu -p regular 05-io-heavy.sbatch
```

Ví dụ cho giảng viên:

```bash
sbatch -A lecture -p regular 03-cpu-heavy.sbatch
```

### Chạy tất cả bằng 1 lệnh

```bash
chmod +x run-all.sh
./run-all.sh stu regular
```

Cho giảng viên:

```bash
./run-all.sh lecture regular
```

## 3) Theo dõi kết quả

```bash
squeue -u $USER
sacct -u $USER --format=JobID,JobName,Partition,Account,State,Elapsed,ExitCode
ls -lah logs/
```
