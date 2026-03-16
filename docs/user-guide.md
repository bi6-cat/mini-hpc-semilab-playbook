# Hướng Dẫn Sử Dụng HPC Semi-Lab
# User Guide — Dành Cho Sinh Viên & Giảng Viên

> **Tên cụm:** `hpc-semi-lab` | **Login Node:** `login01.lab.local`
> **Phiên bản tài liệu:** 2.0 | **Cập nhật:** 2026-03-16
> **Audience:** Sinh viên (`g_stu`) · Giảng viên (`g_lec`) · Khách (`g_guest`)

**Các con số về tài nguyên chỉ để tham khảo**
---

## Mục Lục

1. [Tổng Quan Hệ Thống](#1-tổng-quan-hệ-thống)
2. [Kết Nối SSH Vào Login Node](#2-kết-nối-ssh-vào-login-node)
3. [Đăng Nhập Desktop Qua X2Go (GUI)](#3-đăng-nhập-desktop-qua-x2go-gui)
4. [Cấu Trúc Storage](#4-cấu-trúc-storage)
5. [Submit Job với Slurm](#5-submit-job-với-slurm)
6. [Resource Limits Theo Nhóm](#6-resource-limits-theo-nhóm)
7. [Job Script Mẫu](#7-job-script-mẫu)
8. [Quy Định Sử Dụng Hệ Thống](#8-quy-định-sử-dụng-hệ-thống)
9. [FAQ & Lỗi Thường Gặp](#9-faq--lỗi-thường-gặp)

---

## 1. Tổng Quan Hệ Thống

### 1.1 Hệ Thống Là Gì?

**HPC Semi-Lab** là cụm tính toán hiệu năng cao (High-Performance Computing) dành cho mục đích **học tập và nghiên cứu**. Hệ thống cho phép bạn:

- Chạy các bài toán tính toán nặng (simulation) trên nhiều CPU cùng lúc
- Truy cập môi trường Linux đầy đủ với giao diện dòng lệnh hoặc desktop đồ họa (X2Go)
- Chia sẻ dữ liệu với nhóm nghiên cứu qua thư mục `/proj`
- Sử dụng phần mềm, tools được cài sẵn trong `/soft`

> **Quan trọng:** `login01` là nơi bạn **đăng nhập và quản lý job**. Các tính toán nặng phải được submit qua Slurm — không chạy trực tiếp trên login node.

### 1.2 Thông Tin Tài Khoản

Tài khoản của bạn được Admin tạo và gửi qua email. Email chứa:
- **Username** (ví dụ: `nguyenvana`)
- **Password tạm thời** — **đổi ngay sau lần đăng nhập đầu tiên**
- Hướng dẫn kết nối

---

## 2. Kết Nối SSH Vào Login Node

### 2.1 Điều Kiện

- Máy tính của bạn phải trong mạng nội bộ (hoặc VPN nếu truy cập từ ngoài)
- Cần có SSH client:
  - **Linux / macOS:** có sẵn (`ssh` trong terminal)
  - **Windows:** dùng [Windows Terminal]

### 2.2 Lệnh Kết Nối

```bash
ssh <username>@login01.lab.local
```

Ví dụ:

```bash
ssh nguyenvana@login01.lab.local
```

Lần đầu kết nối, SSH hỏi xác nhận fingerprint — nhập `yes`.

### 2.3 Đổi Password Ngay Sau Lần Đăng Nhập Đầu Tiên

```bash
passwd
# Current password: <nhập password tạm thời>
# New password:     <nhập password mới>
# Retype:           <nhập lại>
```

### 2.4 Cấu Hình SSH Lưu Thông Tin (Tùy Chọn)

Để không phải gõ đầy đủ địa chỉ mỗi lần, thêm vào file `~/.ssh/config` **trên máy tính của bạn**:

```
Host hpc-login
    HostName login01.lab.local
    User nguyenvana
    IdentityFile ~/.ssh/id_ed25519
```

Sau đó kết nối chỉ cần:

```bash
ssh hpc-login
```

### 2.5 Dùng SSH Key (Khuyến Nghị)

Dùng SSH key thay password để an toàn và tiện hơn:

```bash
# Tạo key trên máy của bạn (tạo 1 lần)
ssh-keygen -t ed25519 -C "your.email@example.com"

# Copy public key lên login node
ssh-copy-id -i ~/.ssh/id_ed25519.pub nguyenvana@login01.lab.local
```

Từ lần kế tiếp sẽ không cần nhập password khi SSH.

---

## 3. Đăng Nhập Desktop Qua X2Go (GUI)

X2Go cho phép bạn truy cập giao diện desktop đồ họa **XFCE** của `login01` từ xa — có thể chạy ứng dụng đồ họa, trình duyệt file, Text Edit...

### 3.1 Cài X2Go Client

Tải về tại: **https://wiki.x2go.org/doku.php/doc:installation:x2goclient**

| Hệ Điều Hành | Tải Về |
|---|---|
| Windows | X2Go Client for Windows (.exe) |
| macOS   | X2Go Client for macOS (.dmg) |
| Linux   | `sudo dnf install x2goclient` hoặc `sudo apt install x2goclient` |

### 3.2 Tạo Session Mới

Mở X2Go Client → **Session** → **New Session**:

| Tùy Chọn         | Giá Trị                |
|------------------|------------------------|
| Session name     | `HPC Semi-Lab`         |
| Host             | `login01.lab.local`    |
| Login / Username | `<username của bạn>`   |
| SSH port         | `22`                   |
| Session type     | **XFCE**               |

Nhấn **OK** để lưu.

### 3.3 Kết Nối

1. Nhấp đúp vào session vừa tạo
2. Nhập **password** (hoặc chọn file SSH key nếu dùng)
3. Chờ vài giây — desktop XFCE sẽ xuất hiện

### 3.4 Lưu Ý Khi Sử Dụng X2Go

- **Không chạy tính toán nặng trong cửa sổ terminal của X2Go desktop** — submit qua Slurm thay thế
- Để tạm ngắt kết nối mà không thoát session: chọn **Session → Suspend** (session vẫn còn trên server)
- Để thoát hoàn toàn: chọn **Logout** trong desktop XFCE trước khi đóng X2Go

---

## 4. Cấu Trúc Storage

Tất cả dữ liệu được lưu trên **storage01** (NFS server) và tự động mount khi bạn đăng nhập. Dữ liệu nhất quán trên tất cả node (login01, compute01/02).

### 4.1 Ba Thư Mục Chính

| Thư Mục         | Mục Đích                              | Quota                 | Ghi/Đọc |
|-----------------|---------------------------------------|-----------------------|---------|
| `/home/<user>` | Home directory cá nhân của bạn        | Theo nhóm (xem 4.2)  | Đọc + Ghi |
| `/proj/<tên>`  | Dữ liệu dự án — chia sẻ trong nhóm   | Không giới hạn riêng  | Đọc + Ghi |
| `/soft`        | Phần mềm khoa học cài sẵn bởi Admin  | —                     | Chỉ đọc |

### 4.2 Quota Disk Theo Nhóm

Quota là **tổng dung lượng dùng chung của cả nhóm** — không phải quota cá nhân:

| Nhóm     | Soft Limit | Hard Limit | Ghi Chú |
|----------|-----------|------------|---------|
| `g_stu`  | 280 GB    | 300 GB     | Tổng toàn bộ sinh viên trong nhóm |
| `g_lec`  | 180 GB    | 200 GB     | Tổng toàn bộ giảng viên trong nhóm |
| `g_guest`| 18 GB     | 20 GB      | Hạn chế thấp nhất |

**Soft limit:** Khi vượt ngưỡng này, hệ thống cảnh báo và bắt đầu đếm grace period 7 ngày.
**Hard limit:** Hệ thống **từ chối ghi thêm** — không upload, không tạo file mới được.

**Kiểm tra dung lượng đang dùng:**

```bash
# Xem quota của nhóm bạn
quota -g $(id -gn)

# Xem dung lượng tổng thư mục home
du -sh ~

# Xem dung lượng /home (tổng cụm)
df -h /home
```

### 4.3 Tổ Chức Thư Mục Gợi Ý

```
/home/<username>/
├── projects/         ← Code, script của từng dự án
│   ├── project_a/
│   └── project_b/
├── results/          ← Kết quả đầu ra job
└── tmp/              ← File tạm, output debug

/proj/<tên_dự_án>/    ← Dữ liệu chia sẻ với cả nhóm
├── data/             ← Dữ liệu đầu vào (dataset lớn)
├── results/          ← Kết quả cuối cùng
└── shared_code/      ← Code dùng chung
```

### 4.4 Phần Mềm Trong `/soft`

```bash
# Xem danh sách phần mềm có sẵn
ls /soft/

# Nếu có Environment Modules
module avail

# Nếu có Conda
source /soft/conda/etc/profile.d/conda.sh
conda activate <env_name>
```

> Liên hệ Admin để yêu cầu cài thêm phần mềm vào `/soft`.

---

## 5. Submit Job với Slurm

**Slurm** là hệ thống quản lý và lập lịch tính toán của cụm. Bạn viết **job script** (file bash), submit lên Slurm, và Slurm tự tìm node trống để chạy.

### 5.1 Các Lệnh Cơ Bản

| Lệnh | Chức Năng |
|------|-----------|
| `sbatch script.sh` | Submit một job script |
| `squeue` | Xem tất cả jobs đang chạy / chờ |
| `squeue -u $USER` | Xem jobs của bạn |
| `scancel <jobid>` | Huỷ một job |
| `scancel -u $USER` | Huỷ tất cả jobs của bạn |
| `sinfo` | Xem trạng thái các node và partition |
| `scontrol show job <jobid>` | Chi tiết một job |
| `sacct -u $USER` | Lịch sử job đã chạy |

### 5.2 Submit Job

```bash
# Soạn script (xem ví dụ tại 7.)
vim my_job.sh

# Submit
sbatch my_job.sh
# Submitted batch job 143

# Kiểm tra trạng thái
squeue -u $USER
```

### 5.3 Đọc Output Của Job

Mặc định Slurm ghi output vào `slurm-<jobid>.out` trong thư mục bạn submit:

```bash
# Xem output realtime khi job đang chạy
tail -f slurm-143.out

# Xem sau khi job xong
cat slurm-143.out
```

### 5.4 Trạng Thái Job

| Trạng Thái | Ký Hiệu | Ý Nghĩa |
|------------|---------|---------|
| PENDING    | PD      | Đang chờ node trống |
| RUNNING    | R       | Đang chạy trên compute node |
| COMPLETED  | CG → (biến mất) | Chạy xong thành công |
| FAILED     | F       | Lỗi — xem file output để debug |
| CANCELLED  | CA      | Đã bị huỷ |
| TIMEOUT    | TO      | Vượt quá thời gian cho phép |

### 5.5 Xem Thông Tin Cluster

```bash
# Trạng thái các node
sinfo
# PARTITION  AVAIL  TIMELIMIT  NODES  STATE  NODELIST
# regular*   up     infinite       2   idle  compute[01-02]

# Chi tiết resources có sẵn
sinfo -o "%n %C %m"
# NODELIST  CPUS(A/I/O/T)  MEMORY
# compute01  0/12/0/12      30720
```

### 5.6 Huỷ Job

```bash
# Huỷ job theo job ID
scancel 143

# Huỷ tất cả jobs của bạn
scancel -u $USER

# Huỷ chỉ jobs đang PENDING
scancel --state=PENDING -u $USER
```

### 5.7 Kiểm Tra Lịch Sử Job

```bash
# Jobs trong 7 ngày qua
sacct -u $USER --starttime=$(date -d "7 days ago" +%Y-%m-%d) \
  --format=JobID,JobName,Partition,CPUTime,State,ExitCode

# Chi tiết một job cụ thể
sacct -j 143 --format=JobID,AllocCPUS,MaxRSS,Elapsed,State
```

---

## 6. Resource Limits Theo Nhóm

### 6.1 Giới Hạn Trên Login Node

Khi bạn SSH vào `login01`, hệ thống tự động áp dụng giới hạn tài nguyên theo nhóm. Giới hạn này áp dụng cho **toàn bộ phiên làm việc của bạn trên login01** (không phải jobs Slurm):

| Nhóm     | CPU Tối Đa | RAM Tối Đa | Submit Job Slurm |
|----------|-----------|------------|------------------|
| `g_lec`  | 8 cores   | 16 GB      | Có               |
| `g_stu`  | 4 cores   | 8 GB       | Có               |
| `g_guest`| 2 cores   | 4 GB       | Không            |

> **`g_guest`:** Tài khoản khách chỉ có thể dùng login01 cho các tác vụ nhẹ (đọc tài liệu, soạn code nhỏ). Không được submit job lên compute nodes.

### 6.2 Tài Nguyên Trên Compute Node (Qua Slurm)

Mỗi compute node có: **12 CPU cores** và **30 GB RAM**.

Cụm hiện có 2 compute nodes (compute01, compute02) → tổng cộng **24 cores** và **60 GB RAM**.

Slurm phân bổ theo yêu cầu trong job script (`--ntasks`, `--cpus-per-task`, `--mem`). Không có giới hạn riêng theo nhóm trên compute.

### 6.3 P

### 6.4 Kiểm Tra Giới Hạn Của Phiên Hiện Tại

```bash
# Xem CPU quota và RAM limit phiên hiện tại
systemctl show user-$(id -u).slice -p CPUQuota -p MemoryMax 2>/dev/null \
  || echo "Không áp dụng (chưa đăng nhập qua SSH session mới)"
```


---

## 7. Job Script Mẫu

Job script là file bash với các **directive Slurm** bắt đầu bằng `#SBATCH`. Lưu với đuôi `.sh` và submit bằng `sbatch`.

### 7.1 Cấu Trúc Cơ Bản

```bash
#!/bin/bash
#SBATCH --job-name=<tên_job>         # Tên hiển thị trong squeue
#SBATCH --output=slurm-%j.out        # %j = job ID
#SBATCH --error=slurm-%j.err         # File ghi lỗi (nếu tách riêng)
#SBATCH --partition=regular          # Partition mặc định
#SBATCH --ntasks=<số_task>           # Số tiến trình song song (MPI)
#SBATCH --cpus-per-task=<n>          # Số CPU trên mỗi task (OpenMP/thread)
#SBATCH --mem=<N>G                   # RAM tổng cộng (ví dụ: 4G, 8G)
#SBATCH --time=<hh:mm:ss>            # Thời gian tối đa (0 = không giới hạn)
#SBATCH --mail-type=END,FAIL         # Gửi email khi xong/lỗi (nếu có cấu hình)
#SBATCH --mail-user=your@email.com

# Lệnh thực thi
```

### 7.2 Job Serial (1 CPU, 1 Task)

```bash
#!/bin/bash
#SBATCH --job-name=my_serial_job
#SBATCH --output=slurm-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=01:00:00

echo "Job bắt đầu: $(date)"
echo "Chạy trên node: $(hostname)"
echo "Thư mục hiện tại: $(pwd)"

# Thay bằng lệnh thực tế của bạn
python3 my_script.py --input data.csv --output result.csv

echo "Job kết thúc: $(date)"
```

Submit:

```bash
sbatch serial_job.sh
```

### 7.3 Job Multi-Thread (OpenMP / 1 Node, Nhiều Core)

```bash
#!/bin/bash
#SBATCH --job-name=openmp_job
#SBATCH --output=slurm-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8          # Dùng 8 CPU cores trên 1 node
#SBATCH --mem=16G
#SBATCH --time=02:00:00

# Truyền số threads vào OpenMP
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

echo "Chạy với $OMP_NUM_THREADS threads trên $(hostname)"

# Ví dụ: Python với multiprocessing
python3 -c "
import multiprocessing
print(f'CPU available: {multiprocessing.cpu_count()}')
# code của bạn ở đây
"

# Hoặc: chương trình OpenMP đã biên dịch
./my_openmp_program
```

### 7.4 Job MPI (Nhiều Process, Có Thể Nhiều Node)

```bash
#!/bin/bash
#SBATCH --job-name=mpi_job
#SBATCH --output=slurm-%j.out
#SBATCH --ntasks=8                  # 8 MPI processes
#SBATCH --ntasks-per-node=4         # 4 process trên mỗi node
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=04:00:00

echo "MPI job với $SLURM_NTASKS tasks"
echo "Nodes: $SLURM_NODELIST"

# Kích hoạt môi trường MPI nếu cần
# module load openmpi  # hoặc
# source /soft/openmpi/env.sh

mpirun -np $SLURM_NTASKS ./my_mpi_program input.dat output.dat
```

### 7.5 Job Python với Conda Environment

```bash
#!/bin/bash
#SBATCH --job-name=python_conda
#SBATCH --output=slurm-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=03:00:00

# Kích hoạt conda
source /soft/conda/etc/profile.d/conda.sh
conda activate my_env

echo "Python: $(python --version)"
echo "Conda env: $CONDA_DEFAULT_ENV"

python3 my_analysis.py

conda deactivate
```

### 7.6 Job Array (Chạy Nhiều Lần Với Tham Số Khác Nhau)

Hữu ích khi cần chạy cùng một script với nhiều bộ tham số khác nhau (sweep parameter):

```bash
#!/bin/bash
#SBATCH --job-name=param_sweep
#SBATCH --output=slurm-%A_%a.out    # %A = array job ID, %a = task index
#SBATCH --array=1-10                # Chạy 10 task, index từ 1 đến 10
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=01:00:00

# SLURM_ARRAY_TASK_ID là index của task hiện tại (1, 2, ..., 10)
echo "Array task ID: $SLURM_ARRAY_TASK_ID"

# Ví dụ: chạy với tham số học khác nhau
LEARNING_RATES=(0.001 0.002 0.005 0.01 0.02 0.05 0.1 0.2 0.5 1.0)
LR=${LEARNING_RATES[$((SLURM_ARRAY_TASK_ID - 1))]}

echo "Chạy với learning rate = $LR"
python3 train.py --learning-rate $LR --output results/lr_${LR}.json
```

Submit và theo dõi:

```bash
sbatch array_job.sh
# Submitted batch job 200

squeue -u $USER
# JOBID   PARTITION  NAME          USER   ST  TIME  NODES  NODELIST
# 200_1   regular    param_sweep   usera  R   0:30  1      compute01
# 200_2   regular    param_sweep   usera  PD  0:00  1      (None)
# ...
```

### 7.7 Job Yêu Cầu 1 Node Đầy Đủ

```bash
#!/bin/bash
#SBATCH --job-name=full_node
#SBATCH --output=slurm-%j.out
#SBATCH --nodes=1                   # Đúng 1 node
#SBATCH --ntasks-per-node=12        # Dùng hết 12 cores
#SBATCH --exclusive                 # Không chia sẻ node với job khác
#SBATCH --mem=0                     # mem=0 = dùng hết RAM của node
#SBATCH --time=08:00:00

echo "Chạy độc quyền trên node: $(hostname)"
./heavy_simulation
```

> **Lưu ý:** `--exclusive` giữ toàn bộ node — nên dùng khi thực sự cần, để tránh lãng phí tài nguyên của người khác.

---

## 8. Quy Định Sử Dụng Hệ Thống

### 8.1 Không Chạy Tính Toán Nặng Trực Tiếp Trên Login Node

Login node (`login01`) là điểm vào **chung của tất cả người dùng**. Chạy tính toán nặng trực tiếp trên đây sẽ làm chậm hệ thống cho mọi người.

**Không được phép trên login node:**

```bash
# SAI — chạy trực tiếp
python3 heavy_training.py          # ❌ KO
./simulation_1000_steps            # ❌ KO
find / -name "*.dat" | xargs ...   # ❌ KO (gây load I/O cao)
```

**Đúng — submit qua Slurm:**

```bash
# ĐÚNG — viết script và submit
sbatch my_job.sh                   # ✓ OK
```

**Được phép trên login node:** soạn code, debug nhanh (< 1 phút), kiểm tra dữ liệu, squeue/sinfo, chạy lệnh nhẹ.

### 8.2 Bảo Mật Tài Khoản

- **Không chia sẻ password** với ai, kể cả Admin IT (Admin không bao giờ hỏi password của bạn)
- Đổi password tạm thời ngay sau lần đăng nhập đầu tiên
- Nếu nghi ngờ tài khoản bị xâm phạm: liên hệ Admin ngay lập tức
- Khi không dùng, **log out khỏi X2Go desktop** (không chỉ đóng cửa sổ)

### 8.3 Chỉ Lưu Dữ Liệu Học Tập / Nghiên Cứu

Tài nguyên lưu trữ có hạn và chia sẻ cho toàn bộ người dùng. Chỉ lưu dữ liệu liên quan đến học tập, nghiên cứu, và bài tập:

- ✓ Dataset, code, kết quả thí nghiệm
- ✓ Môi trường Conda, phần mềm cho nghiên cứu
- ✗ Phim, nhạc, ảnh cá nhân
- ✗ Game, phần mềm commercial không liên quan

Dọn dẹp các file và kết quả cũ không còn cần thiết để nhường quota cho người khác.

### 8.4 Tự Backup Dữ Liệu Quan Trọng

Hệ thống **không đảm bảo backup tự động** cho `/home` và `/proj`. Dữ liệu quan trọng cần được sao lưu ra ngoài (máy cá nhân hoặc cloud):

```bash
# Ví dụ: sync từ /home về máy cá nhân
rsync -avz --progress nguyenvana@login01.lab.local:~/projects/ ./hpc_backup/
```

---

## 9. FAQ & Lỗi Thường Gặp

### Đăng Nhập / SSH

**Q: Quên password, không đăng nhập được.**

Liên hệ Admin IT để reset password:
> **Email hỗ trợ:** [admin@lab.local]

---

**Q: SSH báo `Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)`.**

Thử thêm `-o PreferredAuthentications=password` để ép nhập password:

```bash
ssh -o PreferredAuthentications=password nguyenvana@login01.lab.local
```

Nếu vẫn lỗi → liên hệ Admin kiểm tra tài khoản LDAP.

---

**Q: Kết nối SSH bị treo, không phản hồi.**

Kiểm tra máy tính của bạn đang trong đúng mạng. Nếu qua VPN — kiểm tra VPN đã kết nối chưa. Thử ping:

```bash
ping login01.lab.local
```

---

### X2Go Desktop

**Q: X2Go kết nối được nhưng màn hình đen / trắng, không load desktop.**

- Ngắt kết nối, chờ 5-10 giây, kết nối lại
- Nếu có session cũ đang treo: trong X2Go Client tìm session cũ, click **Terminate** rồi tạo session mới

**Q: X2Go rất lag / chậm.**

Giảm màu sắc trong cài đặt session: **Session Settings** → **Connection** → **Connection speed: LAN** hoặc giảm xuống **MODEM**.

---

### Storage & Quota

**Q: Không tạo được file mới: `Disk quota exceeded`.**

Quota của nhóm đã đầy. Xóa bớt file không cần thiết:

```bash
# Tìm 10 file/thư mục lớn nhất
du -sh ~/* | sort -rh | head -10

# Tìm file lớn hơn 1GB
find ~ -size +1G -type f 2>/dev/null
```

Liên hệ Admin nếu cần tăng quota.

---

**Q: `/home`, `/proj`, `/soft` không mount (không thấy dữ liệu).**

```bash
ls /home /proj /soft
```

Nếu trống hoặc lỗi → NFS mount bị gián đoạn. Đăng xuất và đăng nhập lại. Nếu vẫn lỗi → liên hệ Admin.

---

### Slurm / Job

**Q: Job không chạy, mãi PENDING (`PD`).**

```bash
# Xem lý do PENDING
squeue -u $USER -o "%.10i %.9P %.8T %.20R"
# Cột cuối là lý do (Resources, Priority, ...)
```

- **`(Resources)`**: không đủ node trống → chờ job khác xong
- **`(Priority)`**: có job ưu tiên cao hơn đang đợi
- **`(AssocGrpCPUMinutesLimit)`**: tài khoản không có Slurm association → liên hệ Admin

---

**Q: Job luôn FAILED ngay khi submit.**

Kiểm tra output file lỗi:

```bash
cat slurm-<jobid>.out
# hoặc:
cat slurm-<jobid>.err
```

Lỗi thường gặp:

| Lỗi Trong Output | Nguyên Nhân | Cách Sửa |
|---|---|---|
| `No such file or directory` | Đường dẫn file input sai | Kiểm tra lại path input trong script |
| `command not found` | Phần mềm chưa load | Thêm `source /soft/conda/...` hoặc `module load ...` |
| `Permission denied` | Không có quyền đọc file | Kiểm tra `ls -l <file>` |
| `slurmstepd: error: ... memory` | Vượt `--mem` | Tăng `--mem` trong script |

---

**Q: Muốn xem job đang chạy dùng tài nguyên bao nhiêu.**

```bash
# Kết nối vào compute node đang chạy job (thay compute01 bằng node thực tế)
ssh compute01

# Xem processes của bạn
top -u $USER

# Thoát
exit
```

---

**Q: Tài khoản `g_guest` không submit được job.**

Tài khoản khách (`g_guest`) **không có quyền submit** job lên compute nodes. Đây là giới hạn chính sách. Liên hệ Admin nếu cần nâng cấp tài khoản.

---

### Phần Mềm

**Q: Cần cài thêm gói Python / package nhưng không có quyền `sudo`.**

Cài trong home directory của bạn:

```bash
pip3 install --user <package>
# Hoặc dùng conda environment riêng:
conda create -n myenv python=3.10
conda activate myenv
conda install <package>
```

**Q: Muốn dùng phần mềm chưa có trong `/soft`.**

Liên hệ Admin IT yêu cầu cài thêm vào `/soft`. Cung cấp tên phần mềm, phiên bản, và mục đích sử dụng.

---

**Liên Hệ Hỗ Trợ:**

> Nếu gặp vấn đề, liên hệ Admin:
> **Email:** [admin@lab.local]

---

*Xem thêm: [System Architecture](system-architecture.md) | [Admin Guide](admin-guide.md)*
