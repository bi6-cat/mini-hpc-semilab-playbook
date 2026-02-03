# Quản Lý Nhóm Người Dùng HPC

## Tổng Quan

Hệ thống HPC được cấu hình với 3 nhóm người dùng chính:

### 1. **lecture** (Giảng viên)
- **GID**: 10001
- **Quyền**:
  - Có quyền sudo (root access)
  - Truy cập login nodes và head nodes
  - Chạy jobs trên compute nodes
- **Mục đích**: Dành cho giảng viên, giáo viên quản lý hệ thống

### 2. **stu** (Sinh viên)
- **GID**: 10002
- **Quyền**:
  - Không có quyền sudo
  - Chỉ truy cập login nodes
  - Chạy jobs trên compute nodes
- **Mục đích**: Dành cho sinh viên sử dụng HPC cho học tập và nghiên cứu

### 3. **guest** (Khách)
- **GID**: 10003
- **Quyền**:
  - Không có quyền sudo
  - Chỉ truy cập login nodes
  - Không được chạy jobs trên compute nodes
- **Mục đích**: Dành cho người dùng tạm thời, demo

## Cấu Hình

### File cấu hình: `inventory/dev/group_vars/login.yml`

```yaml
user_groups:
  - name: lecture
    gid: 10001
    description: "Lecturers/Teachers Group"
    sudo_access: true
    login_nodes: ['login']
    compute_access: true
  - name: stu
    gid: 10002
    description: "Students Group"
    sudo_access: false
    login_nodes: ['login']
    compute_access: true
  - name: guest
    gid: 10003
    description: "Guest Users Group"
    sudo_access: false
    login_nodes: ['login']
    compute_access: false
```

## Triển Khai

### 1. Chạy playbook cấu hình nhóm người dùng:

```bash
cd /home/hpcadmin/ansible/mini-hpc-semilab-playbook
ansible-playbook -i inventory/dev/hosts.yml playbooks/05-login-gui.yml
```

### 2. Thêm người dùng mới vào nhóm:

**Cách 1: Thêm vào file cấu hình** (khuyên dùng)

Sửa file `inventory/dev/group_vars/login.yml`, thêm vào phần `sample_users`:

```yaml
sample_users:
  # ... người dùng hiện tại
  - username: lecturer02
    firstname: "Nguyen"
    lastname: "Van A"
    email: "lecturer02@lab.local"
    group: lecture
    password: "YourPassword123"
```

Sau đó chạy lại playbook:
```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/05-login-gui.yml
```

**Cách 2: Thêm trực tiếp qua IPA CLI** (cho việc thêm nhanh)

SSH vào head node:
```bash
ssh head01.lab.local

# Lấy Kerberos ticket
echo "Admin@1234" | kinit admin

# Tạo user mới
ipa user-add lecturer02 \
  --first=Nguyen \
  --last="Van A" \
  --email=lecturer02@lab.local \
  --shell=/bin/bash \
  --password

# Thêm user vào nhóm
ipa group-add-member lecture --users=lecturer02
```

## Quản Lý Access Control

### Host-Based Access Control (HBAC)

HBAC rules tự động được tạo cho mỗi nhóm:
- `hbac-lecture`: Cho phép nhóm lecture truy cập login và head nodes
- `hbac-stu`: Cho phép nhóm stu truy cập login nodes
- `hbac-guest`: Cho phép nhóm guest truy cập login nodes

### Kiểm tra HBAC rules:

```bash
# Liệt kê tất cả HBAC rules
ipa hbacrule-find

# Xem chi tiết rule
ipa hbacrule-show hbac-lecture
```

### Sửa đổi quyền truy cập:

Ví dụ: Cho phép sinh viên truy cập head node:

```bash
ipa hbacrule-add-host hbac-stu --hostgroups=head
```

## Sudo Access

Chỉ nhóm `lecture` có quyền sudo thông qua rule `lecture-sudo`.

### Kiểm tra sudo rules:

```bash
ipa sudorule-find
ipa sudorule-show lecture-sudo
```

### Thêm/bớt quyền sudo:

```bash
# Thêm nhóm vào sudo rule
ipa sudorule-add-user lecture-sudo --groups=lecture

# Xóa nhóm khỏi sudo rule
ipa sudorule-remove-user lecture-sudo --groups=lecture
```

## Slurm Integration (Tương lai)

Để kiểm soát quyền chạy jobs theo nhóm, bạn có thể cấu hình Slurm:

### Giới hạn tài nguyên theo nhóm:

Thêm vào `/etc/slurm/slurm.conf`:

```
# Lecturers - unlimited
AccountingStorageEnforce=associations,limits,qos

# Students - limited resources
PartitionName=compute MaxTime=24:00:00 MaxNodes=2 AllowGroups=lecture,stu

# Guests - no compute access (chỉ login)
```

### Tạo QoS (Quality of Service):

```bash
sacctmgr add qos lecture priority=100
sacctmgr add qos student priority=50
sacctmgr add qos guest priority=10
```

## Kiểm Tra & Xác Minh

### 1. Kiểm tra nhóm đã tạo:

```bash
ipa group-find
```

### 2. Kiểm tra thành viên trong nhóm:

```bash
ipa group-show lecture
ipa group-show stu
ipa group-show guest
```

### 3. Test login:

```bash
# Từ máy client
ssh lecturer01@login01.lab.local
ssh student01@login01.lab.local
ssh guest01@login01.lab.local
```

### 4. Test sudo (chỉ lecturer):

```bash
# Login as lecturer01
ssh lecturer01@login01.lab.local
sudo -l  # Nên thấy quyền sudo

# Login as student01
ssh student01@login01.lab.local
sudo -l  # Không có quyền
```

## Troubleshooting

### Lỗi: User không login được

1. Kiểm tra HBAC rules:
```bash
ipa hbacrule-find
```

2. Disable rule `allow_all` nếu muốn strict control:
```bash
ipa hbacrule-disable allow_all
```

3. Kiểm tra SSSD cache:
```bash
sss_cache -E
systemctl restart sssd
```

### Lỗi: Sudo không hoạt động

1. Kiểm tra sudo rule đã enable:
```bash
ipa sudorule-show lecture-sudo
```

2. Clear SSSD sudo cache:
```bash
sss_cache -E
systemctl restart sssd
```

## Bảo Mật

### Đổi mật khẩu mặc định:

**Người dùng tự đổi:**
```bash
ssh lecturer01@login01.lab.local
passwd
```

**Admin đổi cho người dùng:**
```bash
ipa user-mod lecturer01 --password
```

### Chính sách mật khẩu:

```bash
# Tạo password policy cho nhóm
ipa pwpolicy-add lecture --minlength=12 --minlife=1 --maxlife=90

# Xem policy hiện tại
ipa pwpolicy-show
```

## Tài Liệu Tham Khảo

- FreeIPA Documentation: https://www.freeipa.org/page/Documentation
- HBAC Rules: https://www.freeipa.org/page/Howto/HBAC_and_allow_all
- Sudo Rules: https://www.freeipa.org/page/V4/Sudo_Integration
