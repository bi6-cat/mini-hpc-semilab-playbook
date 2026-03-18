# System Architecture & Configuration
# Kiến Trúc & Cấu Hình Hệ Thống HPC Semi-Lab

> **Tên cụm:** `hpc-semi-lab` | **Domain:** `lab.local` | **OS:** Rocky Linux 8 / AlmaLinux 8
> **Phiên bản tài liệu:** 2.1 | **Cập nhật:** 2026-03-16
> **Audience:** Admin / IT / Management

**Lưu ý: Các con số về tài nguyên chỉ là giả định**
---

## Table of Contents / Mục Lục

1. [System Overview](#1-system-overview)
2. [Hardware Topology](#2-hardware-topology)
3. [Network Design](#3-network-design)
4. [Software Stack](#4-software-stack)
5. [Service Dependency Diagram](#5-service-dependency-diagram)
6. [Storage Design](#6-storage-design)
7. [Security Model](#7-security-model)
8. [Key Configuration Reference](#8-key-configuration-reference)

---

## 1. System Overview

### 1.1 Mục Tiêu

Hệ thống **HPC Semi-Lab** là một cụm tính toán hiệu năng cao (HPC) quy mô nhỏ, được xây dựng cho mục đích **giảng dạy và thực hành nghiên cứu**. Hệ thống cung cấp môi trường tính toán chia sẻ, quản lý tập trung, cho phép sinh viên và giảng viên thực hiện các tác vụ tính toán và lưu trữ dữ liệu.

Toàn bộ hạ tầng được quản lý bằng **Ansible** (Infrastructure as Code), đảm bảo khả năng kiểm soát phiên bản và cấu hình.

### 1.2 Phạm Vi

- **Người dùng mục tiêu:** Sinh viên (`stu`), giảng viên (`lecture`), khách (`guest`)
- **Workload:** Mô phỏng, tính toán, chạy phần mềm, kiểm thử bán dẫn
- **Môi trường:** Semi-lab — phù hợp giáo dục, phòng nghiên cứu
- **Hạ tầng:** Cụm máy chủ nội bộ

---

## 2. Hardware Topology

### 2.1 Danh Sách Node

| Hostname    | IP Address     | Role           | Chức năng chính                                                    |
|-------------|----------------|----------------|------------------------------------------------------------|
| `head01`    | 192.168.56.10  | Head / Control | Slurm Controller, LDAP Server, Monitoring Hub              |
| `login01`   | 192.168.56.20  | Login / Access | Điểm đăng nhập của người dùng, cung cấp X2Go GUI desktop  |
| `compute01` | 192.168.56.30  | Compute Worker | Slurm worker node, thực thi compute job                    |
| `compute02` | 192.168.56.31  | Compute Worker | Slurm worker node, thực thi compute job                    |
| `storage01` | 192.168.56.50  | Storage Server | NFS server — export `/home`, `/proj`, `/soft`              |

### 2.2 Vai Trò Chi Tiết Từng Node

#### head01 — Control Node
- Trung tâm điều phối toàn bộ cụm
- Dịch vụ chạy: `389-ds` (LDAP), `slurmctld`, `slurmdbd`, `mariadb`, `prometheus`, `grafana`, `node_exporter`, `slurm_exporter`
- NFS client: mount `/proj` và `/soft` từ storage01; **không** mount `/home` để tránh xung đột với home directory cục bộ của `hpcadmin`
- Là Ansible control node — deploy trực tiếp qua `ansible_connection: local`

#### login01 — Login Node
- Điểm duy nhất người dùng SSH vào để tương tác với cụm
- Cung cấp X2Go + XFCE desktop session cho người dùng cần GUI
- NFS client: mount `/home`, `/proj` (rw) và `/soft` (ro) từ storage01
- Áp dụng giới hạn tài nguyên login per-group qua systemd cgroups (PAM hook)
- Dịch vụ chạy: `sssd`, `x2goserver`, `node_exporter`

#### compute01, compute02 — Worker Nodes
- Nhận và thực thi job từ `slurmctld` thông qua daemon `slurmd`
- Tài nguyên mỗi node: **12 CPU cores**, **30 GB RAM** (cấu hình giả định, override trong inventory)
- NFS client: mount `/home`, `/proj` (rw) và `/soft` (ro) từ storage01
- Dịch vụ chạy: `slurmd`, `sssd`, `node_exporter`

#### storage01 — Storage Node
- Lưu trữ tập trung cho toàn bộ cụm
- NFS server — export `/home`, `/proj`, `/soft` cho mạng `192.168.56.0/24`
- Disk quota theo nhóm (group quota) được bật trên toàn bộ filesystem
- Không chạy Slurm; không có SSSD/LDAP client

---

## 3. Network Design

### 3.1 Sơ Đồ Mạng

```
Internet / External DNS (8.8.8.8, 1.1.1.1)
         |
         | NAT/Bridge trên hypervisor host
         |
┌────────────────────────── 192.168.56.0/24 ─────────────────────────────┐
│                                                                         │
│  head01            login01         compute01       compute02            │
│  .10               .20             .30             .31                  │
│                                                                         │
│  [389-ds   :389]   [SSH     :22]   [slurmd :6818]  [slurmd :6818]       │
│  [slurmctld:6817]  [X2Go    :22]   [sssd        ]  [sssd        ]       │
│  [slurmdbd :6819]  [sssd        ]  [node-exp:9100]  [node-exp:9100]     │
│  [Prom     :9090]  [node-exp:9100]                                      │
│  [Grafana  :3000]                                                       │
│  [node-exp :9100]                                 storage01             │
│  [slurm-exp:9341]                                 .50                   │
│                                                   [NFS :2049]           │
│                                                   [rpcbind :111]        │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Cấu Hình Mạng

| Thông Số          | Giá Trị                                       |
|-------------------|-----------------------------------------------|
| Cluster network   | `192.168.56.0/24`                             |
| Domain nội bộ     | `lab.local`                                   |
| FQDN head node    | `head01.lab.local`                            |
| External DNS      | `8.8.8.8` (Google), `1.1.1.1` (Cloudflare)    |
| Phân giải nội bộ  | `/etc/hosts` trên tất cả node                 |


### 3.3 Cổng Dịch Vụ Quan Trọng

| Dịch Vụ         | Cổng        | Protocol | Node               |
|-----------------|-------------|----------|--------------------|
| SSH / X2Go      | 22          | TCP      | Tất cả node        |
| LDAP            | 389         | TCP      | head01             |
| LDAPS (roadmap) | 636         | TCP      | head01             |
| slurmctld       | 6817        | TCP      | head01             |
| slurmd          | 6818        | TCP      | compute01/02       |
| slurmdbd        | 6819        | TCP      | head01             |
| NFS             | 2049        | TCP/UDP  | storage01          |
| rpcbind         | 111         | TCP/UDP  | storage01          |
| node_exporter   | 9100        | TCP      | Tất cả node        |
| slurm_exporter  | 9341        | TCP      | head01             |
| Prometheus      | 9090        | TCP      | head01             |
| Grafana         | 3000        | TCP      | head01             |

> **Lưu ý:** X2Go sử dụng tunnel qua SSH port 22 — không cần mở port riêng cho X2Go.

---

## 4. Software Stack

### 4.1 Bảng Tóm Tắt Phần Mềm

| Lớp               | Phần Mềm                   | Phiên Bản / Nguồn                  | Node                 |
|-------------------|----------------------------|------------------------------------|----------------------|
| OS                | Rocky Linux 8 / AlmaLinux 8 | 8.x (el8)                         | Tất cả               |
| Identity Server   | 389 Directory Server       | 1.4 (RHEL 8 AppStream)             | head01               |
| Identity Client   | SSSD                       | (RHEL 8 repo)                      | head01, login01, compute* |
| Job Scheduler     | Slurm (OpenHPC 2.x)        | 23.02 (repos.openhpc.community)    | Tất cả trừ storage01 |
| Slurm Auth        | MUNGE                      | (OpenHPC repo)                     | Tất cả trừ storage01 |
| Slurm Accounting  | slurmdbd + MariaDB         | (OpenHPC + RHEL 8)                 | head01               |
| Shared Storage    | NFS (NFSv3)                | nfs-utils (RHEL 8)                 | Tất cả               |
| Disk Quota        | quota                      | (RHEL 8 repo)                      | storage01            |
| Remote Desktop    | X2Go + XFCE                | x2goserver (rpms.x2go.org)         | login01              |
| Monitoring        | Prometheus                 | prometheus2 (PackageCloud)         | head01               |
| Monitoring        | Grafana                    | grafana (grafana.com repo)         | head01               |
| Monitoring        | node_exporter              | node_exporter (PackageCloud)       | Tất cả               |
| Monitoring        | slurm_exporter             | (custom / community build)         | head01               |
| Automation        | Ansible                    | (trên hpcadmin control host)       | head01               |
| Resource Limits   | systemd cgroups via PAM    | (RHEL 8 built-in)                  | login01              |

### 4.2 Thứ Tự Khởi Động Dịch Vụ

Các dịch vụ trọng yếu phải khởi động đúng thứ tự để cụm hoạt động bình thường:

```
1. storage01   → NFS server sẵn sàng (export /home, /proj, /soft)
       ↓
2. head01      → 389-ds (LDAP) sẵn sàng
       ↓
3. Tất cả node → SSSD kết nối LDAP thành công → user/group resolution hoạt động
       ↓
4. head01      → MUNGE key sẵn sàng → MariaDB → slurmdbd → slurmctld khởi động
       ↓
5. compute01/02→ MUNGE → slurmd khởi động → đăng ký với slurmctld
       ↓
6. head01      → Prometheus + Grafana + node_exporter (độc lập, không block)
```

---

## 5. Service Dependency Diagram

Sơ đồ phụ thuộc dịch vụ toàn cụm:

```
┌──────────────────────────────────────────────────────────┐
│                     head01.lab.local                     │
│                                                          │
│   ┌─────────────┐    ┌──────────────────────────────┐    │
│   │ 389-ds(LDAP)│    │  Monitoring Stack            │    │
│   │  :389       │    │  Prometheus :9090            │    │
│   └──────┬──────┘    │    ← node_exporter (all)     │    │
│          │           │    ← slurm_exporter :9341    │    │
│          │ LDAP auth │  Grafana :3000               │    │
│          │           │    ← datasource: Prometheus  │    │
│   ┌──────▼──────┐    └──────────────────────────────┘    │
│   │  MariaDB    │                                        │
│   │  :3306      │                                        │
│   └──────┬──────┘                                        │
│          │ accounting DB                                 │
│   ┌──────▼──────┐                                        │
│   │  slurmdbd   │◄── MUNGE auth                          │
│   │  :6819      │                                        │
│   └──────┬──────┘                                        │
│          │                                               │
│   ┌──────▼──────┐                                        │
│   │ slurmctld   │◄───────────────────────────────────────┼── slurmd :6818 (compute01)
│   │  :6817      │◄───────────────────────────────────────┼── slurmd :6818 (compute02)
│   └─────────────┘                                        │
│                                                          │
└──────────────────────────────────────────────────────────┘
         ↑                          ↑
    LDAP clients (SSSD)        NFS mounts
    login01, compute*          login01, compute*, head01


┌─────────────────────┐      ┌──────────────────────────────┐
│     storage01       │      │          login01             │
│                     │      │                              │
│  NFS server         │      │  SSSD ──► LDAP (head01:389)  │
│  /home → rw ────────┼──────►  X2Go + XFCE desktop         │
│  /proj → rw ────────┼──────►  Login limits (cgroups/PAM)  │
│  /soft → ro ────────┼──────►  User SSH entry point        │
│                     │      │  node_exporter :9100         │
│  Disk quota         │      └──────────────────────────────┘
│  (group quota)      │
└─────────────────────┘
```

---

## 6. Storage Design

### 6.1 Mountpoints NFS

| Mountpoint | Export từ  | Mục Đích                                          | Mount tại                              | Quyền |
|------------|------------|---------------------------------------------------|----------------------------------------|-------|
| `/home`    | storage01  | Home directory của người dùng LDAP                | login01, compute01, compute02          | rw    |
| `/proj`    | storage01  | Dữ liệu dự án nhóm, chia sẻ giữa các job          | head01, login01, compute01, compute02  | rw    |
| `/soft`    | storage01  | Phần mềm khoa học, môi trường conda/spack         | head01, login01, compute* (ro)         | ro    |

> **Lưu ý quan trọng:** `head01` không mount `/home` để tránh xung đột với home directory cục bộ của user `hpcadmin` — tài khoản Ansible admin chạy trực tiếp trên head01.

### 6.2 NFS Mount Options

Mount NFS sử dụng tùy chọn chuẩn: `rw,hard,intr,nfsvers=3,tcp,rsize=1048576,wsize=1048576`

| Tùy Chọn              | Ý Nghĩa                                                          |
|-----------------------|------------------------------------------------------------------|
| `rw`                  | Mount read-write (trừ `/soft` là read-only)                      |
| `hard,intr`           | Tự động kết nối lại khi NFS server gián đoạn tạm thời            |
| `nfsvers=3`           | NFSv3 — đã kiểm tra tương thích với EL 8                         |
| `tcp`                 | Transport qua TCP, ổn định hơn UDP với file lớn                  |
| `rsize=1048576`       | Read buffer 1 MB — tối ưu throughput đọc                         |
| `wsize=1048576`       | Write buffer 1 MB — tối ưu throughput ghi                        |

### 6.3 Disk Quota (Group Quota)

Quota áp dụng theo nhóm (group quota) — toàn bộ user trong nhóm dùng chung pool. Cấu hình tại `inventory/dev/group_vars/storage.yml`:

| Nhóm      | Soft Limit | Hard Limit | Ghi Chú                              |
|-----------|------------|------------|--------------------------------------|
| `g_stu`   | 280 GB     | 300 GB     | Pool chung toàn bộ nhóm sinh viên    |
| `g_lec`   | 180 GB     | 200 GB     | Pool chung toàn bộ nhóm giảng viên   |
| `g_guest` | 18 GB      | 20 GB      | Hạn chế thấp nhất cho tài khoản khách |

**Cơ chế hoạt động:**
- Khi sử dụng đạt **soft limit** → hệ thống cảnh báo và bắt đầu đếm grace period (mặc định 7 ngày)
- Khi vượt **hard limit** → hệ thống từ chối ghi thêm dữ liệu

**Warning message khi vượt soft limit:**

```
dquot: warning, group quota exceeded on /home for group g_stu (uid 10002)
```

User sẽ thấy cảnh báo này mỗi lần thực hiện lệnh ghi (`touch`, `mkdir`, `cp`, etc.) nếu nhóm đã vượt soft limit. User vẫn ghi được dữ liệu cho đến khi chạm hard limit.

### 6.4 Cấu Trúc Thư Mục

```
/home/
├── hpc.test/          ← Test user (UID: 20000, GID: 20000)
└── <username>/        ← Home directory mỗi LDAP user
    └── .ssh/          ← SSH keys (từ sshPublicKey attribute trong LDAP)

/proj/
└── <project>/         ← Thư mục dự án (admin tạo thủ công, chown theo nhóm)

/soft/
├── modules/           ← Environment modules (nếu triển khai)
├── conda/             ← Conda environments dùng chung
└── <software>/        ← Phần mềm khoa học cài đặt bởi admin
```

---

## 7. Security Model

### 7.1 Quản Lý Bí Mật (Secrets Management)

Tất cả mật khẩu và giá trị nhạy cảm được lưu trong **Ansible Vault** theo inventory/group. Playbook chạy với `--ask-vault-pass`; không phụ thuộc `source .env`.

| Vault Variable                     | Dùng Bởi                                   | Mô Tả                                                               |
|------------------------------------|--------------------------------------------|---------------------------------------------------------------------|
| `ldap_directory_manager_password`  | `ldap-server`, `identity-ldap`             | Password `cn=Directory Manager` — quyền tối cao 389-ds             |
| `ldap_bind_password`               | `ldap-client`                              | Password bind DN `cn=admin,...` cho SSSD                           |
| `ldap_useradmin_password`          | user-management scripts                    | Password `cn=hpc-useradmin` — scoped service account               |
| `ldap_test_user_password`          | `identity-ldap` role                       | Password user test `hpc.test`                                      |
| `mariadb_root_password`            | `slurm-controller` role                    | Root password MariaDB                                               |
| `mariadb_slurm_password`           | `slurm-controller` role                    | Password user `slurm` trong MariaDB                                 |
| `grafana_admin_password`           | `grafana-server` role                      | Grafana admin password                                              |
| `smtp_host/smtp_user/smtp_password`| user-management scripts                    | SMTP config gửi welcome/reset email                                 |
| `smtp_port/smtp_from`              | user-management scripts                    | SMTP port và địa chỉ người gửi                                      |

Các vault file theo `inventory/dev/group_vars/{all,head}/vault.yml` phải được mã hoá bằng `ansible-vault encrypt` trước khi deploy. Riêng script quản trị user đọc secrets từ file runtime root-only `/etc/hpc/user-management-secrets.env` do Ansible render từ Vault.


### 7.2 Chuỗi Xác Thực (Authentication Chain)

```
Người dùng
    │
    ▼ SSH (port 22)
login01
    │
    ▼ PAM → SSSD  [ldap_access_filter: uidNumber>=10000 — chặn account không phải HPC user]
head01:389 (389 Directory Server / LDAP, StartTLS enabled)
    │
    ▼ LDAP simple bind (username + password, kênh mã hoá STARTTLS)
Xác thực thành công → tạo session → áp dụng login limits (cgroups PAM)
```

Hiện tại xác thực qua **LDAP simple bind** trên kênh STARTTLS. Không có Kerberos.

### 7.3 Authorization & Resource Limits

**Giới Hạn Tài Nguyên Trên Login Node (`login01`):**

| Nhóm      | CPU Quota | RAM Limit | Truy Cập Compute Slurm |
|-----------|-----------|-----------|------------------------|
| `g_lec`   | 8 cores   | 16 GB     | Có                     |
| `g_stu`   | 4 cores   | 8 GB      | Có                     |
| `g_guest` | 2 cores   | 4 GB      | Không                  |

Giới hạn được áp dụng qua **systemd slice cgroups**, kích hoạt khi người dùng SSH login (PAM session hook). File cấu hình: `/etc/hpc/login-limits.conf`.

**Phân Bổ Tài Nguyên Trên Compute Node (qua Slurm):**

Scheduler sử dụng `select/cons_tres` với `CR_Core_Memory` — phân bổ theo **core và memory** (không cấp toàn bộ node). Granularity: 1 core + RAM tương ứng.

### 7.4 Admin Access Policy

- User `hpcadmin` là tài khoản Ansible/admin duy nhất, có `sudo NOPASSWD:ALL` trên tất cả node
- Nhóm `hpcadmins` trong LDAP cho phép mở rộng quyền admin trong tương lai
- User thường (`g_lec` / `g_stu` / `g_guest`) **không có sudo** trên bất kỳ node nào
- Root login qua SSH bị tắt (mặc định trên RHEL 8 derivatives)

**Scoped Service Account — `cn=hpc-useradmin`:**

Thay vì dùng `cn=Directory Manager` (quyền tối cao) trong script vận hành ngày thường, hệ thống có tài khoản `cn=hpc-useradmin,dc=lab,dc=local` với quyền tối giản:

| Phạm Vi                     | Quyền được cấp                         | Mục đích                                    |
|-----------------------------|----------------------------------------|---------------------------------------------|
| `ou=people,dc=lab,dc=local` | `read, search, compare, add, delete, write` | Tạo / xóa user entry              |
| `ou=groups,dc=lab,dc=local` | `read, search, compare, write` trên attribute `memberUid` | Cập nhật thành viên nhóm |

Script `create-hpc-user.sh` và `delete-hpc-user.sh` bind bằng `cn=hpc-useradmin` qua biến `LDAP_USERADMIN_PASSWORD`. `cn=Directory Manager` chỉ được dùng bởi Ansible khi deploy.

### 7.5 Trạng Thái TLS / Mã Hóa

| Thành Phần    | Hiện Tại                                    |
|---------------|---------------------------------------------|
| LDAP          | **StartTLS bật** — `ldap://:389` + STARTTLS |
| NFS           | Cleartext (NFSv3)                           |
| Slurm (MUNGE) | HMAC-SHA1 credential                        |
| SSH           | OpenSSH (mã hóa transport mặc định)         |
| Grafana       | HTTP                                        |
| Prometheus    | HTTP                                        |

> **LDAP StartTLS:** Client SSSD dùng `ldap_id_use_start_tls: true` + `ldap_tls_reqcert: allow`. Toàn bộ tra cứu identity và bind xác thực đều đi qua kênh mã hóa dù vẫn dùng port 389.

### 7.6 SSSD Access Control & SELinux

**SSSD `ldap_access_filter`:**

Role `ldap-client` áp dụng filter trên tất cả SSSD client (login01, compute*):

```
sssd_ldap_access_filter: "(uidNumber>=10000)"
```

Chỉ LDAP account có `uidNumber ≥ 10000` (user HPC) mới được phép đăng nhập hệ thống. System account bị chặn ở tầng SSSD, không chỉ ở PAM.

**SELinux:**

| Node                       | `selinux_state`                   | Ghi chú                                         |
|----------------------------|-----------------------------------|-------------------------------------------------|
| head01, login01, storage01 | Cấu hình qua `all.yml`            | SELinux boolean `authlogin_nsswitch_use_ldap`, `use_nfs_home_dirs` chỉ được set khi `enforcing` |
| compute01, compute02       | `permissive` (override trong `compute.yml`) | Tránh vỡ Slurm jobs do policy chưa được tune   |

Role `os` và `security` xử lý SELinux state, boolean, và port labeling theo biến `selinux_state` của từng node group.

---

## 8. Key Configuration Reference

### 8.1 Sơ Đồ File Cấu Hình Ansible

```
mini-hpc-semilab-playbook/
├── ansible.cfg                       ← Ansible config chung
├── inventory/dev/
│   ├── hosts.yml                     ← Danh sách node và IP address
│   └── group_vars/
│       ├── all/
│       │   ├── vars.yml              ← Biến public toàn cụm (LDAP, Slurm, groups, NFS paths)
│       │   └── vault.yml             ← Vault duy nhất (toàn bộ secrets)
│       ├── head.yml                  ← Biến head node (monitoring ports, NFS mounts)
│       ├── login.yml                 ← Biến login node (GUI enabled, NFS mounts)
│       ├── compute.yml               ← Biến compute node (CPU/RAM config, NFS mounts)
│       └── storage.yml               ← Biến storage node (NFS exports, quota limits)
├── playbooks/
│   ├── 00-bootstrap.yml
│   ├── 01-identity.yml
│   ├── 02-storage.yml
│   ├── 03-login-gui.yml
│   ├── 04-slurm-head.yml
│   ├── 05-slurm-compute.yml
│   └── 06-monitoring.yml
└── roles/                            ← 21 roles (xem bảng 8.3)
```

### 8.2 Biến Quan Trọng trong `group_vars/all/vars.yml`

#### Cluster Identity
```yaml
cluster_name: hpc-semi-lab
domain_name:  lab.local
timezone:     Asia/Ho_Chi_Minh
admin_user:   hpcadmin
admin_group:  hpcadmins
```

#### LDAP
```yaml
ldap_domain:              lab.local
ldap_base_dn:             dc=lab,dc=local
ldap_server_host:         head01.lab.local
ldap_port:                389              # StartTLS bật — mã hóa trên port 389
ldap_secure_port:         636              # LDAPS (upgrade roadmap nếu cần)
ldap_user_base:           ou=people,dc=lab,dc=local
ldap_group_base:          ou=groups,dc=lab,dc=local
ldap_bind_dn:             cn=admin,dc=lab,dc=local      # Read-only bind DN cho SSSD
ldap_useradmin_dn:        cn=hpc-useradmin,dc=lab,dc=local  # Scoped service account cho create/delete-hpc-user.sh
ldap_ds_instance:         instance         # Tên 389-ds instance
```

#### Slurm
```yaml
slurm_cluster_name:              hpc-lab        # Tên trong slurmdbd (lowercase)
slurm_version:                   23.02
slurm_control_machine:           head01
slurm_control_addr:              192.168.56.10
slurm_accounting_storage_type:   accounting_storage/slurmdbd
slurm_scheduler_type:            sched/backfill
slurm_select_type:               select/cons_tres
slurm_select_type_parameters:    CR_Core_Memory
slurm_slurmctld_port:            6817
slurm_slurmd_port:               6818
slurm_slurmdbd_port:             6819
slurm_max_job_count:             10000
slurm_max_array_size:            1000
```

#### Slurm Accounts (ánh xạ tới LDAP groups)
```yaml
slurm_accounts:
  - name: g_lec    # Giảng viên
  - name: g_stu    # Sinh viên
  - name: g_guest  # Khách
```

#### Compute Node Resources (`group_vars/compute.yml`)
```yaml
cpu_cores:   12      # CPU cores mỗi node
memory_gb:   30      # RAM mỗi node (GB)
# → slurm_cpu_count: 12, slurm_real_memory: 30720 (MB)
```

#### Slurm Partition
```yaml
slurm_partitions:
  - name: tiny
    nodes: "compute[01-02]"
    default: "NO"
    max_time: "1:00:00"
    MaxCPUsPerNode: 4
    MaxMemPerCPU: 4096
    DefMemPerCPU: 2048
    state: UP
    max_nodes: 2
  - name: small
    nodes: "compute[01-02]"
    default: "YES"
    max_time: "4:00:00"
    MaxCPUsPerNode: 8
    MaxMemPerCPU: 4096
    DefMemPerCPU: 2048
    state: UP
    max_nodes: 2
  - name: medium
    nodes: "compute[01-02]"
    default: "NO"
    max_time: "12:00:00"
    MaxCPUsPerNode: 16
    MaxMemPerCPU: 4096
    DefMemPerCPU: 2048
    state: UP
    max_nodes: 2
  - name: large
    nodes: "compute[01-02]"
    default: "NO"
    max_time: "24:00:00"
    MaxCPUsPerNode: 32
    MaxMemPerCPU: 4096
    DefMemPerCPU: 2048
    state: UP
    max_nodes: 2
  - name: infinite
    nodes: "compute[01-02]"
    default: "NO"
    max_time: "INFINITE"
    AllowGroups: "g_lec,hpcadmins"
    state: UP
    max_nodes: 2
```

#### User Groups & Login Limits
```yaml
user_groups:
  - name:           g_lec
    gid:            10001
    login_cpu:      8        # CPU quota trên login node
    login_mem_gb:   16       # RAM limit trên login node
    compute_access: true
  - name:           g_stu
    gid:            10002
    login_cpu:      4
    login_mem_gb:   8
    compute_access: true
  - name:           g_guest
    gid:            10003
    login_cpu:      2
    login_mem_gb:   4
    compute_access: false    # Không được submit job Slurm
```

#### NFS Paths & Quota (`group_vars/storage.yml`)
```yaml
nfs_home: /home
nfs_proj: /proj
nfs_soft: /soft

quota_group_limits:
  - groupname: g_stu      soft_gb: 280  hard_gb: 300
  - groupname: g_lec      soft_gb: 180  hard_gb: 200
  - groupname: g_guest    soft_gb: 18   hard_gb: 20
```

#### Monitoring Ports
```yaml
# group_vars/all/vars.yml
node_exporter_port:  9100
slurm_exporter_port: 9341

# group_vars/head.yml
prometheus_port:              9090
grafana_port:                 3000
prometheus_scrape_interval:   15s
prometheus_evaluation_interval: 15s
prometheus_retention_time:    15d
```

### 8.3 Ansible Roles Map

| Role                 | Chạy trên                    | Chức Năng                                          |
|----------------------|------------------------------|----------------------------------------------------|
| `common`             | Tất cả                       | Packages cơ bản, timezone, hostname                |
| `os`                 | Tất cả                       | OS hardening, repo setup, SELinux                  |
| `security`           | Tất cả                       | SSH config, firewall rules                         |
| `reboot`             | Tất cả (khi cần)             | Reboot handler sau kernel/config thay đổi          |
| `ldap-server`        | head01                       | Cài & cấu hình 389 Directory Server                |
| `identity-ldap`      | head01                       | Khởi tạo DIT (OU people/groups, test user, scripts)|
| `ldap-client`        | login01, compute*            | Cấu hình SSSD kết nối tới LDAP server              |
| `ldap-contract`      | (shared library role)        | Validation contract — kiểm tra LDAP vars trước deploy |
| `nfs-server`         | storage01                    | Cấu hình NFS exports                              |
| `nfs-client`         | head01, login01, compute*    | Mount NFS filesystems                              |
| `quota`              | storage01                    | Cấu hình disk quota theo group                     |
| `slurm-common`       | head01, login01, compute*    | MUNGE key, slurm user/group, shared slurm.conf     |
| `slurm-controller`   | head01                       | slurmctld, slurmdbd, MariaDB, Slurm accounts       |
| `slurm-worker`       | compute01, compute02         | slurmd daemon                                      |
| `login-gui`          | login01                      | X2Go server, XFCE desktop, branding wallpaper      |
| `login-limits`       | login01                      | systemd cgroup limits per user group (via PAM)     |
| `user-privacy`       | login01                      | File permission hardening cho home directories     |
| `prometheus-server`  | head01                       | Prometheus scrape config, targets                  |
| `grafana-server`     | head01                       | Grafana dashboards, datasource Prometheus           |
| `node-exporter`      | Tất cả                       | System metrics exporter (CPU, RAM, disk, network)  |
| `slurm-exporter`     | head01                       | Slurm job/node/partition metrics exporter          |

---

*Xem thêm: [Admin Guide](admin-guide.md) | [User Guide](user-guide.md) | [SOP](sop.md)*
