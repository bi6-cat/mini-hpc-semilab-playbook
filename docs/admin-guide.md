# Admin Operations Guide
# Hướng Dẫn Vận Hành Cho Admin HPC Semi-Lab

> **Tên cụm:** `hpc-semi-lab` | **Domain:** `lab.local` | **Cluster (Slurm):** `hpc-lab`
> **Phiên bản tài liệu:** 2.0 | **Cập nhật:** 2026-03-16
> **Audience:** Admin ITCác giá trị về tài nguyên chỉ để tham khảo

**Các con số về tài nguyên chỉ để tham khảo**
---

## Table of Contents

1. [Prerequisites & Setup Môi Trường Ansible](#1-prerequisites--setup-môi-trường-ansible)
2. [Deployment Flow Phase 00→06](#2-deployment-flow-phase-0006)
3. [LDAP Operations](#3-ldap-operations)
4. [NFS / Storage](#4-nfs--storage)
5. [Slurm Operations](#5-slurm-operations)
6. [Admin Onboarding](#6-admin-onboarding)
7. [Monitoring](#7-monitoring)
8. [Troubleshooting Matrix](#8-troubleshooting-matrix)

---

## 1. Prerequisites & Setup Môi Trường Ansible

### 1.1 Yêu Cầu Control Node

Control node **là chính head01** (`ansible_connection: local`). Tất cả lệnh `ansible-playbook` được chạy trực tiếp từ user `hpcadmin` trên `head01`.

| Thành Phần | Phiên Bản Tối Thiểu | Ghi Chú                               |
|------------|---------------------|---------------------------------------|
| OS         | Rocky Linux 8.x     | Giống các node trong cụm              |
| Python     | 3.6+                | Mặc định trên Rocky 8                 |
| Ansible    | 2.12+               | Cài qua `dnf` hoặc `pip`              |
| Git        | Bất kỳ              | Để clone repo                         |

### 1.2 Cài Đặt Ansible

```bash
# Cách 1: qua dnf (Rocky 8 EPEL)
sudo dnf install -y epel-release
sudo dnf install -y ansible

# Cách 2: qua pip (nếu cần phiên bản mới hơn)
pip3 install --user ansible
```

Kiểm tra phiên bản:

```bash
ansible --version
# ansible [core 2.x.x] ...
```

### 1.3 Clone Repository

```bash
cd ~
git clone <repo_url> ansible/mini-hpc-semilab-playbook
cd ansible/mini-hpc-semilab-playbook
```

### 1.4 Cài Ansible Collections

```bash
ansible-galaxy collection install ansible.posix community.general
```

### 1.5 Cấu Hình File `.env`

```bash
# Tạo file .env từ template
cp .env.example .env
chmod 600 .env

# Chỉnh sửa — điền các giá trị thật
vim .env
```

Các biến bắt buộc phải điền:

| Biến                       | Mô Tả                                           |
|----------------------------|-------------------------------------------------|
| `LDAP_BIND_PASSWORD`       | Password `cn=Directory Manager` (389-ds)         |
| `LDAP_USERADMIN_PASSWORD`  | Password `cn=hpc-useradmin` (cho user scripts)   |
| `MARIADB_ROOT_PASSWORD`    | Root password MariaDB                           |
| `MARIADB_SLURM_PASSWORD`   | Password user `slurm` trong MariaDB             |
| `SMTP_*`                   | SMTP config nếu dùng tính năng gửi email welcome|

> **Quan trọng:** `LDAP_BIND_PASSWORD` (Directory Manager) và `LDAP_USERADMIN_PASSWORD` (scoped service account) là **hai password khác nhau**. Không dùng chung.

**Source .env trước mỗi phiên làm việc Ansible:**

```bash
source ~/.env
# hoặc nếu .env nằm trong repo:
source /home/hpcadmin/ansible/mini-hpc-semilab-playbook/.env
```

### 1.6 Cấu Hình SSH Key

`ansible.cfg` dùng private key tại `/home/hpcadmin/.ssh/id_ed25519`. Key này phải có trong `authorized_keys` của user `hpcadmin` trên tất cả node remote (login01, compute01/02, storage01).

```bash
# Tạo key nếu chưa có
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Copy public key đến các remote node
for node in login01 compute01 compute02 storage01; do
  ssh-copy-id -i ~/.ssh/id_ed25519.pub hpcadmin@${node}.lab.local
done
```

> **head01:** dùng `ansible_connection: local` — không cần SSH key cho chính nó.

### 1.7 Kiểm Tra Kết Nối

```bash
source .env
ansible all -m ping
```

Output mong đợi:

```yaml
head01    | SUCCESS => {"ping": "pong"}
login01   | SUCCESS => {"ping": "pong"}
compute01 | SUCCESS => {"ping": "pong"}
compute02 | SUCCESS => {"ping": "pong"}
storage01 | SUCCESS => {"ping": "pong"}
```

Nếu một node fail → kiểm tra SSH, firewall, hoặc xem [Troubleshooting Matrix §8](#8-troubleshooting-matrix).

---

## 2. Deployment Flow Phase 00→06

### 2.1 Sơ Đồ Tổng Quan

```
Phase 00: Bootstrap → Phase 01: Identity → Phase 02: Storage
       → Phase 03: Login GUI → Phase 04: Slurm Head
       → Phase 05: Slurm Compute → Phase 06: Monitoring
```

**Thứ tự là bắt buộc** — mỗi phase phụ thuộc vào phase trước.

### 2.2 Chuẩn Bị Trước Khi Deploy

```bash
# 1. Vào thư mục repo
cd /home/hpcadmin/ansible/mini-hpc-semilab-playbook

# 2. Load secrets
source .env

# 3. Kiểm tra kết nối toàn cụm
ansible all -m ping

# 4. Dry-run (syntax check trước)
ansible-playbook playbooks/00-bootstrap.yml --syntax-check
```

---

### 2.3 Phase 00 — Bootstrap

**Mục tiêu:** OS hardening, packages cơ bản, timezone, hostname, SSH config, firewall.

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/00-bootstrap.yml
```

**Checkpoint sau Phase 00:**

```bash
# Kiểm tra hostname đúng
ansible all -m command -a "hostname -f"
# Kết quả mong đợi: head01.lab.local, login01.lab.local, ...

# Kiểm tra timezone
ansible all -m command -a "timedatectl show --property=Timezone --value"
# Kết quả: Asia/Ho_Chi_Minh

# Kiểm tra SELinux
ansible all -m command -a "getenforce"
```

---

### 2.4 Phase 01 — Identity (LDAP)

**Mục tiêu:** Cài 389-ds, khởi tạo DIT (OU people/groups, groups `g_lec`/`g_stu`/`g_guest`), tạo user test, deploy scripts tạo/xóa user, tạo `cn=hpc-useradmin`.

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/01-identity.yml
```

**Checkpoint sau Phase 01:**

```bash
# Kiểm tra LDAP service trên head01
ssh head01 systemctl is-active dirsrv@instance
# Active

# Kiểm tra SSSD trên login01
ssh login01 systemctl is-active sssd
# Active

# Test user lookup từ login01
ssh login01 getent passwd hpc.test
# hpc.test:*:20000:20000:HPC Test User:/home/hpc.test:/bin/bash

# Test group lookup
ssh login01 getent group g_stu
# g_stu:*:10002:
```

---

### 2.5 Phase 02 — Storage (NFS)

**Mục tiêu:** Cấu hình NFS server trên storage01, export `/home`/`/proj`/`/soft`, bật disk quota, mount NFS trên các client node.

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/02-storage.yml
```

**Checkpoint sau Phase 02:**

```bash
# Kiểm tra NFS exports từ storage01
ssh storage01 exportfs -v

# Kiểm tra mounts trên login01
ssh login01 df -h /home /proj /soft
# Filesystem: storage01:/home ...

# Kiểm tra quota trên storage01
ssh storage01 repquota -sg /home
```

---

### 2.6 Phase 03 — Login GUI

**Mục tiêu:** Cài X2Go + XFCE trên login01, áp dụng login resource limits (systemd cgroups).

> **Lưu ý:** `gui_enabled: true` phải được set trong `inventory/dev/group_vars/login.yml` (hoặc `host_vars/login01.yml`) trước khi chạy.

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/03-login-gui.yml
```

**Checkpoint sau Phase 03:**

```bash
# Kiểm tra x2goserver
ssh login01 systemctl is-active x2goserver
# Active

# Kiểm tra login limits config
ssh login01 cat /etc/hpc/login-limits.conf
# g_stu: cpu=4, mem=8G
# g_lec: cpu=8, mem=16G
# g_guest: cpu=2, mem=4G

# Kiểm tra PAM hook
ssh login01 grep pam_exec /etc/pam.d/sshd
```

---

### 2.7 Phase 04 — Slurm Head

**Mục tiêu:** Cài MUNGE, MariaDB, slurmdbd, slurmctld, tạo Slurm accounts (`g_lec`/`g_stu`/`g_guest`).

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/04-slurm-head.yml
```

**Checkpoint sau Phase 04:**

```bash
# Kiểm tra services
ssh head01 systemctl is-active munge mariadb slurmdbd slurmctld

# Kiểm tra cluster trong sacctmgr
ssh head01 sacctmgr -n list cluster
# hpc-lab

# Kiểm tra accounts
ssh head01 sacctmgr -n list account
# g_lec, g_stu, g_guest
```

---

### 2.8 Phase 05 — Slurm Compute

**Mục tiêu:** Cài MUNGE, slurmd trên compute01 và compute02, sync MUNGE key từ head01.

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/05-slurm-compute.yml
```

**Checkpoint sau Phase 05:**

```bash
# Kiểm tra node status từ head01
ssh head01 sinfo
# PARTITION  AVAIL  NODES  STATE  NODELIST
# regular*   up     2      idle   compute[01-02]

# Kiểm tra node detail
ssh head01 scontrol show node compute01 | grep -E "State|CPUTot|RealMemory"
```

---

### 2.9 Phase 06 — Monitoring

**Mục tiêu:** Cài node_exporter trên tất cả node, slurm_exporter và Prometheus + Grafana trên head01.

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml
```

**Checkpoint sau Phase 06:**

```bash
# Prometheus health
curl -fsS http://head01.lab.local:9090/-/healthy
# Prometheus is Healthy.

# Grafana health
curl -fsS http://head01.lab.local:3000/api/health
# {"commit":"...","database":"ok","version":"..."}

# Node exporter
curl -fsS http://head01.lab.local:9100/metrics | head -5
```

---

### 2.10 Re-Deploy Một Phase

Chạy lại một phase đơn lẻ mà không ảnh hưởng phần còn lại:

```bash
# Chỉ chạy lại LDAP
ansible-playbook -i inventory/dev/hosts.yml playbooks/01-identity.yml

# Với tag cụ thể
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags grafana

# Chỉ trên một node
ansible-playbook -i inventory/dev/hosts.yml playbooks/05-slurm-compute.yml --limit compute01
```

---

## 3. LDAP Operations

> Tất cả lệnh LDAP chạy trên **head01** với user `hpcadmin`. Load `.env` trước.

### 3.1 Tạo User Mới

Script `create-hpc-user.sh` thực hiện: tạo LDAP entry, thêm vào group, tạo Slurm account, gửi email welcome.

```bash
sudo -E /usr/local/bin/create-hpc-user.sh <username> <group> "<Full Name>" <email>
```

**Ví dụ:**

```bash
# Tạo sinh viên
sudo -E /usr/local/bin/create-hpc-user.sh nguyenvana g_stu "Nguyen Van A" nguyenvana@example.com

# Tạo giảng viên
sudo -E /usr/local/bin/create-hpc-user.sh lectureb g_lec "Lecture B" lectureb@university.edu.vn

# Tạo tài khoản khách
sudo -E /usr/local/bin/create-hpc-user.sh guestu01 g_guest "Guest User 01" guestu01@example.com
```

**Output bao gồm:**
- UID được cấp phát (monotonic counter, không tái sử dụng)
- Password một lần (hiển thị trực tiếp và gửi qua email)
- Status Slurm association
- Status email

> **Lưu ý:** `-E` để truyền biến môi trường (`LDAP_USERADMIN_PASSWORD`, `SMTP_*`) vào sudo.

### 3.2 Xóa User

```bash
sudo -E /usr/local/bin/delete-hpc-user.sh <username>
```

Script sẽ hiển thị thông tin user và yêu cầu xác nhận `y/N` trước khi xóa. Quá trình xóa bao gồm:
1. Xóa `memberUid` khỏi tất cả group LDAP chứa user
2. Xóa user entry khỏi `ou=people`
3. Xóa Slurm accounting association

> **Home directory `/home/<username>` không tự động được xóa.**
> Quyết định giữ hay xóa data là việc của admin:
> ```bash
> # Sau khi xác nhận không cần giữ data
> rm -rf /home/<username>  # chạy trên storage01 hoặc qua NFS
> ```

### 3.3 Liệt Kê & Tìm Kiếm User

```bash
# Liệt kê tất cả user trong LDAP
ldapsearch -LLL -x -H ldap://127.0.0.1:389 \
  -D "cn=Directory Manager" -w "$LDAP_BIND_PASSWORD" \
  -b "ou=people,dc=lab,dc=local" "(objectClass=posixAccount)" uid uidNumber gidNumber cn

# Tìm user cụ thể
ldapsearch -LLL -x -H ldap://127.0.0.1:389 \
  -D "cn=Directory Manager" -w "$LDAP_BIND_PASSWORD" \
  -b "dc=lab,dc=local" "(uid=nguyenvana)"

# Kiểm tra từ client (login/compute)
getent passwd nguyenvana
id nguyenvana
```

### 3.4 Liệt Kê Group & Members

```bash
# Tất cả groups
ldapsearch -LLL -x -H ldap://127.0.0.1:389 \
  -D "cn=Directory Manager" -w "$LDAP_BIND_PASSWORD" \
  -b "ou=groups,dc=lab,dc=local" "(objectClass=posixGroup)" cn gidNumber memberUid

# Group cụ thể
ldapsearch -LLL -x -H ldap://127.0.0.1:389 \
  -D "cn=Directory Manager" -w "$LDAP_BIND_PASSWORD" \
  -b "cn=g_stu,ou=groups,dc=lab,dc=local" -s base memberUid

# Từ client
getent group g_stu
```

### 3.5 Đổi Group Cho User (Chuyển Nhóm)

```bash
# 1. Xóa memberUid khỏi group cũ
ldapmodify -x -H ldap://127.0.0.1:389 \
  -D "cn=hpc-useradmin,dc=lab,dc=local" -w "$LDAP_USERADMIN_PASSWORD" <<EOF
dn: cn=g_stu,ou=groups,dc=lab,dc=local
changetype: modify
delete: memberUid
memberUid: nguyenvana
EOF

# 2. Thêm vào group mới
ldapmodify -x -H ldap://127.0.0.1:389 \
  -D "cn=hpc-useradmin,dc=lab,dc=local" -w "$LDAP_USERADMIN_PASSWORD" <<EOF
dn: cn=g_lec,ou=groups,dc=lab,dc=local
changetype: modify
add: memberUid
memberUid: nguyenvana
EOF

# 3. Cập nhật gidNumber trong user entry
ldapmodify -x -H ldap://127.0.0.1:389 \
  -D "cn=hpc-useradmin,dc=lab,dc=local" -w "$LDAP_USERADMIN_PASSWORD" <<EOF
dn: uid=nguyenvana,ou=people,dc=lab,dc=local
changetype: modify
replace: gidNumber
gidNumber: 10001
EOF

# 4. Cập nhật Slurm account
sacctmgr -i modify user nguyenvana set defaultaccount=g_lec cluster=hpc-lab
```

### 3.6 Reset Password User

```bash
# Tạo hash mới (SSHA512)
NEW_PASS="<password_mới>"
HASHED="$(python3 -c "
import hashlib, base64, os, sys
p = b'${NEW_PASS}'
s = os.urandom(8)
d = hashlib.sha512(p + s).digest()
print('{SSHA512}' + base64.b64encode(d + s).decode())
")"

# Cập nhật vào LDAP
ldapmodify -x -H ldap://127.0.0.1:389 \
  -D "cn=hpc-useradmin,dc=lab,dc=local" -w "$LDAP_USERADMIN_PASSWORD" <<EOF
dn: uid=<username>,ou=people,dc=lab,dc=local
changetype: modify
replace: userPassword
userPassword: ${HASHED}
EOF
```

### 3.7 Troubleshoot SSSD

**SSSD cache cũ — user mới tạo chưa resolve được:**

```bash
# Trên node bị lỗi (login01 hoặc compute*)
sudo sss_cache -E          # xóa toàn bộ cache
sudo systemctl restart sssd

# Kiểm tra lại
getent passwd <username>
id <username>
```

**Xem SSSD log:**

```bash
sudo tail -100 /var/log/sssd/sssd_pam.log
sudo tail -100 /var/log/sssd/sssd_nss.log
sudo tail -100 /var/log/sssd/sssd_LDAP.log
```

**SSSD không kết nối được LDAP:**

```bash
# Test kết nối LDAP thủ công từ node bị lỗi
ldapsearch -LLL -x -H ldap://head01.lab.local:389 \
  -D "cn=admin,dc=lab,dc=local" -w "$LDAP_BIND_PASSWORD" \
  -b "dc=lab,dc=local" "(uid=hpc.test)" uid

# Kiểm tra firewall trên head01
sudo firewall-cmd --list-ports | grep 389
```

**Debug SSSD chi tiết:**

```bash
# Bật debug tạm thời (level 5)
sudo sssctl config-check
sudo sssctl domain-status lab.local
sudo sssctl user-checks <username>
```

---

## 4. NFS / Storage

> Các lệnh liên quan đến NFS server và quota chạy trên **storage01**.
> Các lệnh kiểm tra mount chạy trên node client tương ứng.

### 4.1 Kiểm Tra Trạng Thái NFS

```bash
# Trên storage01 — xem tất cả exports đang active
exportfs -v

# Trên client — xem các mount NFS hiện tại
mount | grep nfs
df -hT /home /proj /soft

# Kiểm tra NFS service
systemctl is-active nfs-server rpcbind    # trên storage01
```

### 4.2 Kiểm Tra Kết Nối NFS Từ Client

```bash
# Test mount thủ công một share
showmount -e storage01.lab.local

# Nếu mount bị treo (stale mount)
sudo umount -f -l /home   # force lazy unmount
sudo mount /home          # remount (dùng entry từ /etc/fstab)
```

### 4.3 Kiểm Tra Disk Quota

```bash
# Trên storage01 — xem quota theo group
sudo repquota -sg /home    # -s = human-readable, -g = group quota

# Quota cho một group cụ thể
sudo quota -sg g_stu

# Từ bất kỳ node nào (qua NFS)
quota -g $(id -gn)         # quota của group hiện tại
```

**Output mẫu:**

```
Block grace time: 7days; Inode grace time: 7days
                        Block limits                File limits
Group           used    soft    hard  grace    used  soft  hard  grace
----------------------------------------------------------------------
g_stu       --  12345M 286720M 307200M           0  0  0
```

### 4.4 Cập Nhật Quota Limit

Thay đổi quota qua Ansible (cách chuẩn — idempotent):

```bash
# 1. Sửa inventory/dev/group_vars/storage.yml
vim inventory/dev/group_vars/storage.yml
# Cập nhật soft_gb / hard_gb của group cần thay đổi

# 2. Apply lại role quota
ansible-playbook -i inventory/dev/hosts.yml playbooks/02-storage.yml --tags quota
```

Thay đổi quota thủ công (tạm thời — sẽ bị ghi đè khi chạy Ansible):

```bash
# Trên storage01
# XFS filesystem
sudo xfs_quota -x -c "limit -g bsoft=300g bhard=320g g_stu" /home

# ext4 filesystem
sudo setquota -g g_stu 314572800 335544320 0 0 /home
# (đơn vị: KB → 300GB = 314572800 KB)
```

### 4.5 Thêm NFS Share Mới

**Ví dụ:** thêm share `/scratch` cho compute nodes.

**Bước 1 — Cập nhật `group_vars/storage.yml`:**

```yaml
nfs_exports:
  # ... existing exports ...
  - path: /scratch
    clients: "192.168.56.0/24"
    options: "rw,sync,no_subtree_check,no_root_squash"
```

**Bước 2 — Thêm mount vào `group_vars/compute.yml`:**

```yaml
nfs_mounts:
  # ... existing mounts ...
  - src: "storage01.lab.local:/scratch"
    path: /scratch
    opts: "rw,hard,intr,nfsvers=3,tcp,rsize=1048576,wsize=1048576"
    fstype: nfs
```

**Bước 3 — Apply:**

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/02-storage.yml
```

**Bước 4 — Kiểm tra:**

```bash
ssh storage01 exportfs -v | grep scratch
ssh compute01 df -h /scratch
```

### 4.6 Tạo Thư Mục Dự Án

```bash
# Trên head01 (qua NFS mount /proj)
sudo mkdir -p /proj/ten-du-an
sudo chown root:g_lec /proj/ten-du-an
sudo chmod 2775 /proj/ten-du-an   # setgid bit: file mới kế thừa group
```

---

## 5. Slurm Operations

> Tất cả lệnh `sacctmgr`, `scontrol`, `squeue`, `scancel` chạy trên **head01**.

### 5.1 Kiểm Tra Trạng Thái Cluster

```bash
# Tổng quan nodes và partitions
sinfo -l

# Chi tiết một node
scontrol show node compute01

# Tất cả jobs đang chạy
squeue -a

# Jobs của một user cụ thể
squeue -u nguyenvana

# Stats tóm tắt
squeue --format="%.10i %.9P %.8j %.8u %.8T %.10M %.9l %.6D %R" -a
```

### 5.2 Drain & Resume Node

**Drain node (ngừng nhận job mới, chờ job hiện tại xong):**

```bash
# Drain với message mô tả lý do
scontrol update NodeName=compute01 State=DRAIN Reason="Maintenance 2026-03-20"

# Kiểm tra trạng thái
sinfo -n compute01
# STATE: draining (đang drain) → drained (đã drain xong, không còn job nào)
```

**Resume node (trở lại nhận job):**

```bash
scontrol update NodeName=compute01 State=RESUME
sinfo -n compute01
# STATE: idle
```

**Drain nhiều node cùng lúc:**

```bash
scontrol update NodeName=compute[01-02] State=DRAIN Reason="Cluster maintenance"
```

### 5.3 Cancel Job

```bash
# Cancel một job cụ thể (biết job ID)
scancel <jobid>

# Cancel tất cả jobs của một user
scancel -u nguyenvana

# Cancel tất cả jobs đang PENDING
scancel --state=PENDING

# Cancel job mà không gửi signal (graceful)
scancel --signal=SIGTERM <jobid>
```

### 5.4 Quản Lý Slurm Accounts (`sacctmgr`)

**Liệt kê accounts và users:**

```bash
# Tất cả accounts trong cluster
sacctmgr -n list account cluster=hpc-lab format=Account,Description,Org

# Tất cả users và account mapping
sacctmgr -n list user cluster=hpc-lab format=User,Account,DefaultAccount

# Association của một user cụ thể
sacctmgr -n list user nguyenvana format=User,Account,Cluster,DefaultAccount
```

**Thêm user vào Slurm account (nếu script create-hpc-user.sh thất bại):**

```bash
sacctmgr -i add user name=nguyenvana \
  account=g_stu \
  cluster=hpc-lab \
  defaultaccount=g_stu
```

**Xóa user khỏi Slurm accounting:**

```bash
sacctmgr -i delete user name=nguyenvana cluster=hpc-lab
```

**Xem lịch sử job của user:**

```bash
sacct -u nguyenvana --format=JobID,JobName,Partition,Account,AllocCPUS,State,ExitCode \
  --starttime=$(date -d "30 days ago" +%Y-%m-%d)
```

### 5.5 Kiểm Tra Services Slurm

```bash
# Trên head01
systemctl status munge slurmdbd slurmctld --no-pager

# Kiểm tra kết nối slurmdbd ↔ slurmctld
scontrol show daemons

# Xem logs
sudo journalctl -u slurmctld -n 50
sudo journalctl -u slurmdbd -n 50

# Trên compute nodes
ssh compute01 systemctl is-active munge slurmd
```

### 5.6 Fix Node ở Trạng Thái `DOWN*` / `drain*`

```bash
# Xem lý do node bị down
sinfo -R

# Reset về idle (sau khi fix vấn đề)
scontrol update NodeName=compute01 State=RESUME

# Nếu vẫn không lên — restart slurmd trên compute node
ssh compute01 sudo systemctl restart slurmd
# Đợi vài giây, rồi kiểm tra lại
sinfo -n compute01
```

---

## 6. Admin Onboarding

> Section này dùng khi cần **setup một admin mới** hoặc **rebuild control node từ đầu**.

### 6.1 Yêu Cầu Trước Khi Bắt Đầu

- Đã có quyền truy cập vào một node trong cụm (hoặc quyền trực tiếp lên các node qua console)
- Có bản sao file `.env` (chứa secrets) lưu ở nơi an toàn

### 6.2 Setup Control Node (head01) Từ Đầu

```bash
# Bước 1: Đăng nhập head01 với user root hoặc sudo-able user
ssh root@head01.lab.local

# Bước 2: Tạo user hpcadmin nếu chưa có
useradd -m -s /bin/bash -G wheel hpcadmin
passwd hpcadmin

# Bước 3: Cấu hình sudo NOPASSWD cho hpcadmin
echo "hpcadmin  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/hpcadmin
chmod 440 /etc/sudoers.d/hpcadmin

# Bước 4: Chuyển sang user hpcadmin
su - hpcadmin

# Bước 5: Tạo SSH key
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Bước 6: Cài Ansible
sudo dnf install -y epel-release git
sudo dnf install -y ansible
ansible-galaxy collection install ansible.posix community.general

# Bước 7: Clone repo
git clone <repo_url> ~/ansible/mini-hpc-semilab-playbook
cd ~/ansible/mini-hpc-semilab-playbook

# Bước 8: Tạo .env từ bản lưu an toàn
cp .env.example .env
chmod 600 .env
vim .env  # điền secrets thực
```

### 6.3 Phân Phối SSH Key Đến Remote Nodes

SSH key của `hpcadmin` trên head01 cần có mặt trong `authorized_keys` trên tất cả remote nodes.

```bash
# Lấy public key
cat ~/.ssh/id_ed25519.pub
# ssh-ed25519 AAAA... hpcadmin@head01.lab.local

# Cách 1: ssh-copy-id (nếu đã có password access)
for node in login01 compute01 compute02 storage01; do
  ssh-copy-id -i ~/.ssh/id_ed25519.pub hpcadmin@${node}.lab.local
done

# Cách 2: Manual (khi không có password auth)
# Đăng nhập từng node, thêm public key vào ~/.ssh/authorized_keys
ssh root@login01 "
  mkdir -p /home/hpcadmin/.ssh
  echo 'ssh-ed25519 AAAA...' >> /home/hpcadmin/.ssh/authorized_keys
  chown -R hpcadmin:hpcadmin /home/hpcadmin/.ssh
  chmod 700 /home/hpcadmin/.ssh
  chmod 600 /home/hpcadmin/.ssh/authorized_keys
"
```

### 6.4 Kiểm Tra Quyền Truy Cập Toàn Cụm

```bash
cd ~/ansible/mini-hpc-semilab-playbook
source .env

# Test SSH connection và sudo
ansible all -m ping
ansible all -m command -a "sudo id" --become

# Test playbook syntax
ansible-playbook playbooks/00-bootstrap.yml --syntax-check
ansible-playbook playbooks/01-identity.yml --syntax-check
```

### 6.5 Thêm Admin IT Mới

Khi thêm một admin IT mới cần quyền quản trị cụm:

```bash
# 1. Thêm public key của admin mới vào authorized_keys trên head01
echo "ssh-ed25519 AAAA... newadmin@workstation" >> ~/.ssh/authorized_keys

# 2. Tùy chọn: thêm vào group hpcadmins trong LDAP
ldapmodify -x -H ldap://127.0.0.1:389 \
  -D "cn=Directory Manager" -w "$LDAP_BIND_PASSWORD" <<EOF
dn: cn=hpcadmins,ou=groups,dc=lab,dc=local
changetype: modify
add: memberUid
memberUid: newadmin
EOF

# 3. Tạo user hpcadmin trên remote nodes nếu dùng account riêng
# (tùy chính sách: cluster này dùng chung 1 user hpcadmin)
```

---

## 7. Monitoring

### 7.1 Kiểm Tra Nhanh Trạng Thái Stack

```bash
# Trên head01 — kiểm tra tất cả monitoring services
systemctl status prometheus grafana-server --no-pager

# Health check
curl -fsS http://127.0.0.1:9090/-/healthy && echo " Prometheus OK"
curl -fsS http://127.0.0.1:3000/api/health && echo " Grafana OK"

# Node exporter trên từng node
for node in head01 login01 compute01 compute02 storage01; do
  echo -n "${node}: "
  curl -fsS --connect-timeout 3 http://${node}.lab.local:9100/metrics > /dev/null \
    && echo "OK" || echo "FAIL"
done

# Slurm exporter
curl -fsS http://127.0.0.1:9341/metrics | grep slurm_nodes_total
```

### 7.2 Kiểm Tra Prometheus Targets

```bash
# Xem trạng thái scrape targets (all UP/DOWN)
curl -fsS 'http://127.0.0.1:9090/api/v1/targets' \
  | python3 -m json.tool \
  | grep -E '"health"|"scrapeUrl"'
```

Hoặc mở trình duyệt: `http://head01.lab.local:9090/targets`

### 7.3 Query Metrics Cơ Bản (PromQL)

```bash
# CPU usage mỗi node (5 phút)
# Trong Prometheus UI: http://head01.lab.local:9090/graph
# Nhập query:
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# RAM used percentage
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

# Disk usage /home
(node_filesystem_size_bytes{mountpoint="/home"} - node_filesystem_free_bytes{mountpoint="/home"}) / node_filesystem_size_bytes{mountpoint="/home"} * 100

# Số jobs đang chạy trong Slurm
slurm_job_states{states="running"}

# Node states
slurm_node_states
```

### 7.4 Grafana — Truy Cập & Thêm Dashboard

**Truy cập:**
```
URL: http://head01.lab.local:3000
```

**Import Dashboard từ Grafana.com:**

1. Đăng nhập Grafana (default: `admin` / `admin` — đổi ngay sau deploy)
2. Menu trái → **Dashboards** → **Import**
3. Nhập Dashboard ID từ [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards):
   - `1860` — Node Exporter Full
   - `4323` — SLURM Scheduler
4. Chọn **Prometheus** datasource → **Import**

**Tạo dashboard thủ công:**

1. **Dashboards** → **New** → **New Dashboard**
2. **Add visualization**
3. Chọn datasource: `Prometheus`
4. Nhập PromQL query → **Apply**
5. **Save dashboard**

### 7.5 Alert Rules

> **Alert rules / Alertmanager chưa implement.** Section này sẽ được bổ sung khi triển khai Alertmanager.
>
> _Placeholder cho:_
> - _Cấu hình Alertmanager (email/Slack routing)_
> - _Alert rules: node down, disk > 80%, CPU > 90%, Slurm node drain_
> - _Hướng dẫn add rule vào `roles/prometheus-server/templates/`_

### 7.6 Re-Deploy Stack Monitoring

```bash
# Toàn bộ monitoring
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml

# Chỉ Prometheus config (sau khi thêm scrape target)
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags prometheus

# Chỉ node-exporter
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags node-exporter

# Chỉ Grafana
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags grafana
```

---

## 8. Troubleshooting Matrix

### 8.1 Kết Nối & Ansible

| Triệu Chứng | Chuẩn đoán lỗi | Cách fix |
|---|---|---|
| `ansible all -m ping` fail một node | SSH key chưa có, firewall, node down | `ssh -v hpcadmin@<node>`, `ping <node>` |
| `UNREACHABLE! Connection timed out` | Node không phản hồi | Kiểm tra VM/server power on; check `ansible_host` IP trong hosts.yml |
| `Permission denied (publickey)` | SSH key chưa distribute | Chạy lại `ssh-copy-id` hoặc thêm key thủ công |
| `sudo: NOPASSWD not configured` | sudoers chưa đúng | Kiểm tra `/etc/sudoers.d/hpcadmin` trên node đó |

### 8.2 LDAP / SSSD

| Triệu Chứng | Chuẩn đoán lỗi | Cách fix |
|---|---|---|
| `getent passwd <user>` trống trên client | SSSD cache cũ; SSSD chưa nhận user mới | `sudo sss_cache -E && sudo systemctl restart sssd` |
| Login SSH bị từ chối (user LDAP mới) | SSSD chưa nhận, home dir chưa tạo, UID ngoài range access filter | Kiểm tra `getent passwd`, xem `/var/log/sssd/sssd_pam.log` |
| `LDAP_USERADMIN_PASSWORD not set` khi chạy script | Chưa `source .env` | `source ~/.env` rồi chạy lại với `sudo -E` |
| `dirsrv@instance.service` fail | 389-ds crash, port 389 bị chiếm | `journalctl -u dirsrv@instance -n 50`; kiểm tra `ss -tlnp | grep 389` |
| SSSD: `Could not start TLS encryption` | StartTLS fail — cert issue | Kiểm tra `ldap_tls_reqcert: allow` trong sssd.conf; restart SSSD |

### 8.3 NFS / Storage

| Triệu Chứng | Chuẩn đoán lỗi | Cách fix |
|---|---|---|
| Mount bị `stale NFS file handle` | storage01 restart hoặc NFS service restart | `sudo umount -f -l /home && sudo mount /home` |
| `df -h` không hiển thị `/home` | Mount fail khi boot | Kiểm tra `/var/log/messages`; `sudo mount -a` để remount |
| `quota: no filesystems with quota detected` | quota chưa được enable | Chạy lại `ansible-playbook playbooks/02-storage.yml --tags quota` |
| User không ghi được file (`Disk quota exceeded`) | Đã vượt hard limit | `repquota -sg /home` để xem; liên hệ admin để tăng quota |
| NFS export không hiện | Thay đổi exports sau khi tắt nfs-server | `ssh storage01 sudo exportfs -ra` để reload exports |

### 8.4 Slurm

| Triệu Chứng | Chuẩn đoán lỗi | Cách fix |
|---|---|---|
| `squeue`: không có output / lỗi connect | `slurmctld` không chạy | `systemctl status slurmctld`; `journalctl -u slurmctld -n 50` |
| Node ở `DOWN*` sau restart | slurmd không kết nối được slurmctld | Kiểm tra MUNGE: `ssh compute01 munge -n | unmunge`; restart slurmd |
| `slurmdbd` fail start | MariaDB chưa sẵn sàng | `systemctl status mariadb`; kiểm tra password trong `.env` |
| Job bị `FAILED` ngay lập tức | User không có Slurm association | `sacctmgr list user <user>`; thêm association thủ công |
| MUNGE auth error trên compute node | MUNGE key không đồng bộ | Copy `/etc/munge/munge.key` từ head01; restart `munge` và `slurmd` |

### 8.5 Monitoring

| Triệu Chứng | Chuẩn đoán lỗi | Cách fix |
|---|---|---|
| Prometheus target `DOWN` | node_exporter không chạy; firewall block port 9100 | `ssh <node> systemctl restart node_exporter`; kiểm tra `firewall-cmd --list-ports` |
| Grafana không load (`502 Bad Gateway`) | Grafana chưa khởi động xong | `systemctl restart grafana-server`; chờ 10 giây rồi retry |
| Prometheus không scrape slurm-exporter | slurm_exporter không chạy | `systemctl status slurm-exporter`; kiểm tra port 9341 |
| Data Grafana bị `No data` | Sai datasource hoặc sai query | Vào **Explore** trong Grafana, test query PromQL trực tiếp |

---

*Xem thêm: [System Architecture](system-architecture.md) | [User Groups](../USERGROUPS.md) | [Monitoring Runbook](monitoring-runbook.md)*
