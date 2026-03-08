# Monitoring Runbook (MVP)

## Scope
- Prometheus + Grafana on `head`
- Node Exporter on `head`, `login`, `compute`, `storage`

## Repository source
- Prometheus and Node Exporter are installed from PackageCloud repo `prometheus-rpm/release`.
- RPM package names used by roles: `prometheus2` and `node_exporter`.

## Apply monitoring stack
```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml
```

## Apply by tags
```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags monitoring
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags prometheus
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags grafana
ansible-playbook -i inventory/dev/hosts.yml playbooks/06-monitoring.yml --tags node-exporter
```

## Note about `--check`
- On first run, avoid `--check` for monitoring install because the repo file is not actually written in check mode, so package tasks can report `No package available`.

## Verify services
```bash
ansible-playbook -i inventory/dev/hosts.yml playbooks/99-verify-v2.yml --tags monitoring
```

## Quick checks
```bash
# On head node
systemctl status prometheus grafana-server --no-pager
curl -fsS http://127.0.0.1:9090/-/healthy
curl -fsS http://127.0.0.1:3000/api/health

# On any node
systemctl status node_exporter --no-pager
curl -fsS http://127.0.0.1:9100/metrics | head
```

## Variables (head group)
File: `inventory/dev/group_vars/head.yml`
- `prometheus_port`
- `grafana_port`
- `node_exporter_port`
- `prometheus_scrape_interval`
- `prometheus_evaluation_interval`
- `prometheus_retention_time`
- `grafana_repo_enabled`
