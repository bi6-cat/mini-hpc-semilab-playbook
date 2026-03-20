# Admin Operations Guide
# Hướng Dẫn Vận Hành Cho Admin HPC Semi-Lab

> **Tên cụm:** `hpc-semi-lab` | **Domain:** `lab.local` | **Cluster (Slurm):** `hpc-lab`
> **Phiên bản tài liệu:** 2.0 | **Cập nhật:** 2026-03-16
> **Audience:** Admin IT

**Lưu ý: Các con số về tài nguyên chỉ là giả định**
---

## Table of Contents

1. [Prerequisites & Setup Môi Trường Ansible](#1-prerequisites--setup-môi-trường-ansible)
2. [Deployment Flow Phase 00→06](#2-deployment-flow-phase-0006)
3. [LDAP Operations](#3-ldap-operations)
4. [NFS / Storage](#4-nfs--storage)
5. [Slurm Operations](#5-slurm-operations)
6. [Monitoring](#6-monitoring)

---

## 1. Prerequisites & Setup Môi Trường Ansible

### 1.1 Yêu Cầu Control Node

Control node **là chính head01** (`ansible_connection: local`). Tất cả lệnh `ansible-playbook` được chạy trực tiếp từ user `hpcadmin` trên `head01`.

| Thành Phần | Phiên Bản Tối Thiểu | Ghi Chú                               |
|------------|---------------------|---------------------------------------|
| OS         | EL 8.x              | Tất cả các node trong cụm              |
| Python     | 3.6+                | Mặc định trên RHEL 8 (Rocky/AlmaLinux) |
| Ansible    | 2.12+               | Cài qua `dnf`                         |
| Git        | Bất kỳ              | Để clone repo                         |

**Bắt buộc trước lần chạy Ansible đầu tiên:** user `hpcadmin` ở mỗi node phải có quyền sudo không hỏi password.

```bash
echo "hpcadmin ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/hpcadmin
sudo chmod 440 /etc/sudoers.d/hpcadmin
sudo visudo -cf /etc/sudoers.d/hpcadmin
```

Nếu thiếu bước này, các lệnh `ansible-playbook --become` có thể bị fail hoặc treo khi chờ nhập sudo password.

### 1.2 Cài Đặt Ansible

```bash
# Cài qua dnf (RHEL 8 EPEL - Rocky/AlmaLinux)
sudo dnf install -y epel-release
sudo dnf install -y ansible
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
# Cần cài nếu phiên bản ansible k tích hợp sẵn
ansible-galaxy collection install ansible.posix community.general
```

### 1.5 Cấu Hình Ansible Vault

```bash
# Tạo/chỉnh sửa secrets đã mã hoá
ansible-vault create inventory/dev/group_vars/all/vault.yml

# Nếu file đã tồn tại
ansible-vault edit inventory/dev/group_vars/all/vault.yml
```

Các biến bắt buộc phải điền:

| Biến                       | Mô Tả                                           |
|----------------------------|-------------------------------------------------|
| `ldap_directory_manager_password` | Password `cn=Directory Manager` (389-ds) |
| `ldap_bind_password`       | Password bind DN `cn=admin,...` cho SSSD         |
| `ldap_useradmin_password`  | Password `cn=hpc-useradmin` (cho user scripts)   |
| `ldap_test_user_password`  | Password test user `hpc.test`                    |
| `mariadb_root_password`    | Root password MariaDB                            |
| `mariadb_slurm_password`   | Password user `slurm` trong MariaDB              |
| `grafana_admin_password`   | Password admin Grafana                            |
| `smtp_host/smtp_user/smtp_password` | SMTP config bắt buộc cho reset password |

> **Quan trọng:** `ldap_directory_manager_password`, `ldap_bind_password`, `ldap_useradmin_password` là các credential khác nhau. Không dùng chung.

**Chạy playbook với Vault password:**

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/00-bootstrap.yml --ask-vault-pass
```

### 1.6 Cấu Hình SSH Key

`ansible.cfg` dùng private key tại `/home/hpcadmin/.ssh/id_ed25519`. Key này phải có trong `authorized_keys` của user `hpcadmin` trên tất cả node remote (login01, compute01/02, storage01).

```bash
# Tạo key nếu chưa có
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Cập nhật /etc/hosts trên head01 để có thể resolve tên node
echo "192.168.1.10 head01.lab.local head01" | sudo tee -a /etc/hosts
echo "192.168.1.20 login01.lab.local login01" | sudo tee -a /etc/hosts
echo "192.168.1.30 compute01.lab.local compute01" | sudo tee -a /etc/hosts
echo "192.168.1.31 compute02.lab.local compute02" | sudo tee -a /etc/hosts
echo "192.168.1.50 storage01.lab.local storage01" | sudo tee -a /etc/hosts

# Copy public key đến các remote node
for node in login01 compute01 compute02 storage01; do
  ssh-copy-id -i ~/.ssh/id_ed25519.pub hpcadmin@${node}.lab.local
done
```

> **head01:** dùng `ansible_connection: local` — không cần SSH key cho chính nó.

### 1.7 Kiểm Tra Kết Nối

```bash
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

Nếu một node fail → kiểm tra SSH, firewall, hoặc xem [Troubleshooting Matrix 8](#8-troubleshooting-matrix).

** Deployment và test nhanh toàn bộ hệ thống với 1 script:**

```bash
# Sau khi đã setup basic environment và Vault, có thể chạy toàn bộ playbooks liên tiếp + smoke tests với 1 lệnh:
./scripts/run-all-playbooks.sh
```

** Script chạy thành công: **
```
=== Summary ===
PASS=40 FAIL=0 SKIP=0
[2026-03-20 13:57:52] Completed successfully
```
---

## 2. Deployment Flow Phase 00→06

> Tất cả lệnh `ansible-playbook` trong section này cần chạy kèm `--ask-vault-pass`.

### 2.1 Sơ Đồ Tổng Quan

```
Phase 00: Bootstrap → Phase 01: Identity → Phase 02: Storage
       → Phase 03: Login GUI → Phase 04: Slurm Head
       → Phase 05: Slurm Compute → Phase 06: Monitoring
```

**Thứ tự là bắt buộc** — mỗi phase phụ thuộc vào phase trước.

### 2.2 Chuẩn Bị Trước Khi Deploy

**Build từ đầu hãy đọc phần chuẩn bị tại mục 6.**

```bash
# 1. Vào thư mục repo
cd /home/hpcadmin/ansible/mini-hpc-semilab-playbook

# 2. Kiểm tra kết nối toàn cụm
ansible all -m ping

# 3. Dry-run (syntax check trước)
ansible-playbook -i inventory/dev/hosts.yml playbooks/00-bootstrap.yml --syntax-check
```

---

### 2.3 Phase 00 — Bootstrap

**Mục tiêu:** OS hardening, packages cơ bản, timezone, hostname, SSH config, firewall.

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/00-bootstrap.yml --ask-vault-pass
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
ansible-playbook -i inventory/dev/hosts.yml playbooks/01-identity.yml --ask-vault-pass
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
ansible-playbook -i inventory/dev/hosts.yml playbooks/02-storage.yml --ask-vault-pass
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
ansible-playbook -i inventory/dev/hosts.yml playbooks/03-login-gui.yml --ask-vault-pass
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
ansible-playbook -i inventory/dev/hosts.yml playbooks/04-slurm-head.yml --ask-vault-pass
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
ansible-playbook -i inventory/dev/hosts.yml playbooks/05-slurm-compute.yml --ask-vault-pass
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
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --ask-vault-pass
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
ansible-playbook -i inventory/dev/hosts.yml playbooks/01-identity.yml --ask-vault-pass

# Với tag cụ thể
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags grafana --ask-vault-pass

# Chỉ trên một node
ansible-playbook -i inventory/dev/hosts.yml playbooks/05-slurm-compute.yml --limit compute01 --ask-vault-pass
```

---

## 3. LDAP Operations

> Tất cả lệnh LDAP chạy trên **head01** với user `hpcadmin`.

### 3.1 Tạo User Mới

Script `create-hpc-user.sh` thực hiện: tạo LDAP entry, thêm vào group, tạo Slurm account, gửi email welcome.

```bash
sudo /usr/local/bin/create-hpc-user.sh <username> <group> "<Full Name>" <email>
```

**Ví dụ:**

```bash
# Tạo sinh viên
sudo /usr/local/bin/create-hpc-user.sh nguyenvana g_stu "Nguyen Van A" nguyenvana@example.com

# Tạo giảng viên
sudo /usr/local/bin/create-hpc-user.sh lectureb g_lec "Lecture B" lectureb@university.edu.vn

# Tạo tài khoản khách
sudo /usr/local/bin/create-hpc-user.sh guestu01 g_guest "Guest User 01" guestu01@example.com
```

**Output bao gồm:**
- UID được cấp phát (monotonic counter, không tái sử dụng)
- Password một lần (hiển thị trực tiếp và gửi qua email)
- Status Slurm association
- Status email

> Script tự đọc secrets từ file root-only: `/etc/hpc/user-management-secrets.env` (được Ansible deploy từ Vault).

### 3.2 Xóa User

```bash
sudo /usr/local/bin/delete-hpc-user.sh <username>
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

### 3.6 User Tự Đổi Password

User có thể tự đổi password của mình bằng lệnh `passwd`:

> **Lưu ý:** Tính năng này yêu cầu ACI "Allow users to change own password" đã được cấu hình trong LDAP.

**Troubleshoot: "Insufficient access rights"**

Nếu user gặp lỗi `Insufficient access rights` khi đổi password, nghĩa là LDAP thiếu ACI cho phép self-password-change. Admin cần thêm ACI sau vào LDAP:


### 3.7 Admin Reset Password User

Admin có thể reset password cho user bằng script tự động hoặc thủ công.

#### 3.7.1 Sử Dụng Script (Khuyến Nghị)

```bash
# Reset password (script sẽ tự tạo password ngẫu nhiên và gửi email)
sudo /usr/local/bin/reset-hpc-user-password.sh <username>
```

**Ví dụ:**

```bash
# Reset password cho user nguyenvana
sudo /usr/local/bin/reset-hpc-user-password.sh nguyenvana

# Output:
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tạo password ngẫu nhiên cho user: nguyenvana
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Full name: Nguyen Van A
# Email    : nguyenvana@example.com
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Xác nhận reset password? (y/N): y
# Password đã được reset thành công
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# NEW PASSWORD: aB3$xY9z (hiển thị trực tiếp và gửi qua email)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Script sẽ:**
- Kiểm tra user có tồn tại
- Tạo password ngẫu nhiên 8 ký tự
- Cập nhật vào LDAP
- Gửi email thông báo cho user (yêu cầu cấu hình SMTP)

> Không cần `sudo -E` sau khi migration Vault hoàn tất.

#### 3.7.2 Thủ Công (Fallback)

Nếu script không khả dụng, reset password thủ công:

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

### 3.8 Troubleshoot SSSD

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

### 4.0 Chính Sách NFS Hiện Tại

Chính sách đang áp dụng theo `inventory/dev/group_vars/storage.yml`:

- `/home`: `rw,sync,no_subtree_check,no_root_squash`
- `/proj`: `rw,sync,no_subtree_check,root_squash`, mode `0770`, ACL `rwx` cho `g_stu` và `g_lec`
- `/soft`: `ro,sync,no_subtree_check,root_squash`

Lưu ý:

- Quyền truy cập thật sự đến từ **filesystem owner/group/mode + ACL** trên `storage01`.
- `nfs_exports.options` chỉ điều khiển chính sách export qua mạng NFS.

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

### 4.7 Thêm Tool Vào `/soft` (Qua Head -> Storage)

Quy trình tối giản để admin thêm tool:

```bash
# 1) SSH vào head, rồi từ head vào storage
ssh hpcadmin@head01.lab.local
ssh hpcadmin@storage01.lab.local

# 2) Tạo thư mục tool theo version
sudo mkdir -p /soft/tools/<tool_name>/<version>/bin

# 3) Copy binary/script vào /soft
sudo cp <local_or_staged_binary> /soft/tools/<tool_name>/<version>/bin/

# 4) Set quyền đọc/execute cho user toàn cụm
sudo chown -R root:root /soft/tools/<tool_name>
sudo find /soft/tools/<tool_name> -type d -exec chmod 755 {} \;
sudo find /soft/tools/<tool_name> -type f -exec chmod 644 {} \;
sudo chmod 755 /soft/tools/<tool_name>/<version>/bin/<binary_name>
```

Kiểm tra từ login node:

```bash
ssh hpcadmin@login01.lab.local
ls -lah /soft/tools/<tool_name>/<version>/bin/
```

`/soft` đang export `ro` cho clients nên thao tác cài đặt phải thực hiện trên `storage01`.

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

### 5.7 Scale thêm Compute Node (ví dụ `compute03`)

Mục này dùng khi mở rộng cụm thêm worker mới mà không rebuild toàn bộ.

**Bước 1 — Thêm host vào inventory**

```bash
# Sửa inventory
vim inventory/dev/hosts.yml
```

Thêm node mới vào group `compute`:

```yaml
compute:
  hosts:
    compute01:
      ansible_host: 192.168.56.30
    compute02:
      ansible_host: 192.168.56.31
    compute03:
      ansible_host: 192.168.56.32
```

**Bước 2 — Cập nhật danh sách node trong Slurm vars**

Thêm sshkey của head01 vào `compute03` (nếu chưa có) để Ansible có thể kết nối khi deploy.

```bash
vim inventory/dev/group_vars/all/vars.yml
```

- Thêm `compute03` vào `slurm_compute_nodes`
- Đổi `nodes: "compute[01-02]"` thành `nodes: "compute[01-03]"` cho các partition
- Tăng `max_nodes` từ `2` → `3` (nếu muốn partition dùng đủ 3 node)

**Bước 3 — Bootstrap node mới**

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/00-bootstrap.yml --limit compute03 --ask-vault-pass
```

**Bước 4 — Cấu hình identity + storage cho node mới**

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/01-identity.yml --limit compute03 --ask-vault-pass
ansible-playbook -i inventory/dev/hosts.yml playbooks/02-storage.yml --limit compute03 --ask-vault-pass
```

**Bước 5 — Regenerate cấu hình Slurm ở head và cài slurmd cho compute03**

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/04-slurm-head.yml --ask-vault-pass
ansible-playbook -i inventory/dev/hosts.yml playbooks/05-slurm-compute.yml --limit compute03 --ask-vault-pass
```

**Bước 6 — Cập nhật monitoring**

```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --ask-vault-pass
```

`06-monitoring.yml` cài `node-exporter` theo group `compute`, nên `compute03` sẽ được thêm tự động sau khi inventory cập nhật.

**Bước 7 — Verify**

```bash
ansible compute03 -m ping
ssh head01 sinfo
ssh head01 scontrol show node compute03 | grep -E "State|CPUTot|RealMemory"
curl -fsS http://head01.lab.local:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="node-exporter") | .discoveredLabels.__address__'
```

Kỳ vọng:
- `compute03` xuất hiện trong `sinfo`
- Trạng thái node `IDLE` hoặc `MIXED`
- Prometheus có target `node-exporter` của `compute03`

---

## 6. Monitoring

### 6.1 Kiểm Tra Nhanh Trạng Thái Stack

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

### 6.2 Kiểm Tra Prometheus Targets

```bash
# Xem trạng thái scrape targets (all UP/DOWN)
curl -fsS 'http://127.0.0.1:9090/api/v1/targets' \
  | python3 -m json.tool \
  | grep -E '"health"|"scrapeUrl"'
```

Hoặc mở trình duyệt: `http://head01.lab.local:9090/targets`

### 6.3 Query Metrics Cơ Bản (PromQL)

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

### 6.4 Grafana — Truy Cập & Thêm Dashboard

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

### 6.5 Alert Rules

> **Alert rules / Alertmanager chưa implement.**
>
> _Placeholder:_
> - _Cấu hình Alertmanager (email/Slack routing)_
> - _Alert rules: node down, disk > 80%, CPU > 90%, Slurm node drain_


### 6.6 Re-Deploy Stack Monitoring

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


*Xem thêm: [System Architecture](system-architecture.md) | [User Groups](../USERGROUPS.md) | [Monitoring Runbook](monitoring-runbook.md)*
