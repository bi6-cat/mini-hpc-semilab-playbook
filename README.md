# Mini HPC Semi-Lab Playbook

Ansible automation cho việc triển khai cụm HPC (High Performance Computing) quy mô nhỏ trên **Rocky Linux 8** hoặc **AlmaLinux 8**.

## Overview

Playbook này tự động hóa việc triển khai một cụm HPC hoàn chỉnh bao gồm:
- LDAP-based identity management (389 Directory Server)
- Slurm workload manager
- OpenHPC 2.x software stack
- NFS shared storage với disk quota
- Environment modules (Lmod)
- X2Go remote desktop (XFCE)
- Monitoring stack (Prometheus/Grafana)

## Supported Operating Systems

- **Rocky Linux 8** (RHEL 8 derivative)
- **AlmaLinux 8** (RHEL 8 derivative)

Cả hai distributions đều tương thích hoàn toàn và hoạt động giống hệt nhau với playbook này.

## Quick Start

```bash
# Clone repository
git clone <repo-url>
cd mini-hpc-semilab-playbook

# Cài Ansible (nếu chưa có)
sudo dnf install -y epel-release ansible

# Cấu hình inventory
vim inventory/dev/hosts.yml

# Chạy bootstrap
ansible-playbook -i inventory/dev/hosts.yml playbooks/00-bootstrap.yml
```

## Documentation

- [System Architecture](docs/system-architecture.md) - Kiến trúc hệ thống
- [Admin Guide](docs/admin-guide.md) - Hướng dẫn vận hành
- [User Guide](docs/user-guide.md) - Hướng dẫn người dùng

## System Requirements

- Rocky Linux 8.x hoặc AlmaLinux 8.x trên tất cả nodes
- Ansible 2.12+ trên control node
- Root/sudo access đến target systems
- Network connectivity giữa các nodes
- Python 3.6+ (mặc định trên RHEL 8)

## Cluster Architecture

| Node Role | Hostname | Services |
|-----------|----------|----------|
| Head/Control | head01 | Slurm Controller, LDAP Server, Monitoring |
| Login | login01 | User login point, X2Go GUI |
| Compute | compute01, compute02 | Slurm worker nodes |
| Storage | storage01 | NFS server, disk quota |

## Deployment Flow

1. **00-bootstrap.yml** - Bootstrap all nodes (OS setup, common packages)
2. **01-identity.yml** - LDAP server and clients
3. **02-storage.yml** - NFS server and mounts
4. **03-login-gui.yml** - X2Go desktop environment
5. **04-slurm-head.yml** - Slurm controller and database
6. **05-slurm-compute.yml** - Slurm worker nodes
7. **06-monitoring.yml** - Prometheus and Grafana

## Key Features

- **Infrastructure as Code**: Toàn bộ hạ tầng được quản lý bằng Ansible
- **Centralized Identity**: LDAP-based authentication và authorization
- **Job Scheduling**: Slurm workload manager với accounting
- **Resource Limits**: CPU, memory, và disk quota enforcement
- **Monitoring**: Real-time metrics và dashboards
- **Security**: SELinux, SSH restrictions, scoped service accounts

