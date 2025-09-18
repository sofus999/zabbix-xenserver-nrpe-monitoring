# Zabbix XenServer NRPE Monitoring Solution

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Zabbix](https://img.shields.io/badge/Zabbix-6.0+-red.svg)](https://www.zabbix.com/)
[![XenServer](https://img.shields.io/badge/XenServer-7.x+-blue.svg)](https://www.citrix.com/products/citrix-hypervisor/)

A comprehensive, enterprise-ready monitoring solution for XenServer/Citrix Hypervisor environments using Zabbix and NRPE agents. This solution provides automated host discovery, real-time performance monitoring, and intelligent alerting for virtualization infrastructure.


## 🚀 Features

- **Automated Host Discovery**: Network scanning with intelligent host detection
- **Comprehensive Metrics**: Host and Dom0 monitoring with 17 different metrics
- **Multi-Interval Load Monitoring**: Separate 1-min, 5-min, and 15-min load averages
- **Robust Error Handling**: Graceful handling of offline hosts and network issues
- **Production Architecture**: File locking, cron automation, and log rotation
- **Scalable Design**: Supports large XenServer environments

## 📊 Monitored Metrics
Reference: [Monitoring host and dom0 resources with NRPE](https://docs.xenserver.com/en-us/xencenter/current-release/performance-nrpe.html)

### 🖥️ Host Level Metrics
| Metric | Description | Units | Thresholds |
|--------|-------------|-------|------------|
| `host.load` | 1-minute load average | - | W:3, C:4 |
| `host.cpu` | Host CPU utilization | % | W:80, C:90 |
| `host.memory` | Host memory utilization | % | W:80, C:90 |
| `host.vgpu` | Virtual GPU utilization | % | W:80, C:90 |
| `host.vgpu_memory` | Virtual GPU memory usage | % | W:80, C:90 |

### 🔧 Dom0 (Control Domain) Metrics
| Metric | Description | Units | Thresholds |
|--------|-------------|-------|------------|
| `dom0.load.1min` | Dom0 1-minute load | - | W:2.7, C:3.2 |
| `dom0.load.5min` | Dom0 5-minute load | - | W:2.6, C:3.1 |
| `dom0.load.15min` | Dom0 15-minute load | - | W:2.5, C:3.0 |
| `dom0.cpu` | Dom0 CPU utilization | % | W:80, C:90 |
| `dom0.memory` | Dom0 memory utilization | % | W:80, C:90 |
| `dom0.swap` | Dom0 swap utilization | % | W:80, C:90 |
| `dom0.disk.root` | Root partition usage | % | W:80, C:90 |
| `dom0.disk.log` | Log partition usage | % | W:80, C:90 |
| `xapi.status` | XAPI service status | - | Binary |
| `multipath.status` | Multipath service status | - | Binary |

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Zabbix Server │    │  Zabbix Proxy   │    │  XenServer Host │
│                 │◄───┤                 │◄───┤                 │
│  - Templates    │    │  - Discovery    │    │  - NRPE Agent   │
│  - Dashboards   │    │  - Collection   │    │  - Monitoring   │
│  - Alerting     │    │  - Caching      │    │  - Scripts      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Data Flow (Trapper Architecture)
- **Push-based**: Data is sent from proxy to Zabbix via `zabbix_sender`
- **Cron-controlled**: Collection frequency managed by cron jobs, not Zabbix intervals
- **Discovery**: Daily at 06:00 (hosts) and 06:05 (metrics)
- **Metrics**: Every minute via `query_xen_server.sh`

## 🚀 Quick Start

### 1. XenServer Configuration

**⚠️ CRITICAL**: Add hostname command to NRPE configuration:

```bash
# Edit /etc/nrpe/nrpe.cfg
echo "command[get_hostname]=/bin/hostname" >> /etc/nrpe/nrpe.cfg
systemctl restart nrpe
```

### 2. Install on Zabbix Proxy

```bash
# Clone repository
git clone https://github.com/sofus999/zabbix-xenserver-nrpe-monitoring.git
cd zabbix-xenserver-nrpe-monitoring

# Deploy scripts
sudo cp Scripts/*.sh /usr/lib/zabbix/externalscripts/
sudo chmod +x /usr/lib/zabbix/externalscripts/*.sh
sudo chown zabbix:zabbix /usr/lib/zabbix/externalscripts/*.sh

# Setup automated monitoring. Replace 
sudo ./setup_cron_jobs.sh \
    --zabbix-server 192.168.1.100 \
    --hostname "<Hostname of Zabbix host>" \
    --ip-ranges "<IP Range to discover>" \
    --user zabbix
```

### 3. Import Zabbix Templates

1. **Configuration > Templates > Import**
2. Import `templates/zbx_template_discover.yaml`
3. Import `templates/zbx_template_checks.yaml`
4. Import `templates/zbx_export_hosts.yaml`


## 📈 Monitoring Dashboard

After successful setup, you'll see automatic host discovery and comprehensive monitoring:
<img width="1714" height="799" alt="image" src="https://github.com/user-attachments/assets/ad36f860-2088-4899-92e0-a8038151c650" />



**Features shown:**
- ✅ 25 XenServer hosts discovered automatically
- ✅ Real-time performance metrics
- ✅ Health status indicators
- ✅ Trend analysis graphs

## ⚡ Advanced Features

### Intelligent Load Average Parsing
```bash
# Raw NRPE output:
"OK - load average per CPU: 0.06, 0.07, 0.06|load1=0.058;2.700;3.200;0; load5=0.065;2.600;3.100;0; load15=0.061;2.500;3.000;0;"

# Parsed values:
dom0.load.1min  → 0.058 (from load1=)
dom0.load.5min  → 0.065 (from load5=)  
dom0.load.15min → 0.061 (from load15=)
```

### Automated Scheduling
- **Host Discovery**: Daily at 06:00 (finds new hosts)
- **Metrics Discovery**: Daily at 06:05 (configures monitoring)
- **Metrics Collection**: Every minute (gathers performance data)

### Production-Ready Features
- **File Locking**: Prevents concurrent cache modifications
- **Error Recovery**: Handles offline hosts gracefully
- **Log Rotation**: Weekly rotation with 1-month retention
- **Path Isolation**: Works in restricted cron environments


## 🔧 Configuration Examples

### NRPE Configuration (`/etc/nrpe/nrpe.cfg`)
```ini
# CRITICAL: Hostname discovery
command[get_hostname]=/bin/hostname

# Host monitoring
command[check_host_load]=/usr/lib64/nagios/plugins/check_load -w 3,4,5 -c 4,5,6
command[check_host_cpu]=/usr/lib64/nagios/plugins/check_cpu.sh
command[check_host_memory]=/usr/lib64/nagios/plugins/check_memory.sh

# Dom0 monitoring  
command[check_load]=/usr/lib64/nagios/plugins/check_load -w 2.7,2.6,2.5 -c 3.2,3.1,3.0
command[check_cpu]=/usr/lib64/nagios/plugins/check_cpu -w 80 -c 90
command[check_memory]=/usr/lib64/nagios/plugins/check_memory -w 80 -c 90
```

### Cron Schedule
```bash
# Host Discovery (daily at 06:00)
0 6 * * * /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh "10.62.7.0/24" --trapper --hostname "XenServer Discovery" --zabbix-server 192.121.42.195 >> /var/log/zabbix/xenapp_host_discovery.log 2>&1

# Metrics Discovery (daily at 06:05)  
5 6 * * * /usr/lib/zabbix/externalscripts/discover_xenapp_metrics.sh --trapper --zabbix-server 192.121.42.195 >> /var/log/zabbix/xenapp_metrics_discovery.log 2>&1

# Metrics Collection (every minute)
* * * * * /usr/lib/zabbix/externalscripts/query_xen_server.sh --trapper --zabbix-server 192.121.42.195 >> /var/log/zabbix/xenapp_metrics_discovery.log 2>&1 >> /var/log/zabbix/xenapp_metrics.log 2>&1
```

## 🛠️ Troubleshooting

### Quick Diagnostics
```bash
# Test NRPE connectivity
check_nrpe -H <xenserver-ip> -c get_hostname

# Test discovery manually
sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh "192.168.1.0/24" --trapper --debug

# Check logs
tail -f /var/log/zabbix/xenapp_*.log
```

### Common Issues
| Issue | Cause | Solution |
|-------|-------|----------|
| "Root privileges required" | nmap scan type | ✅ Fixed (uses TCP scan) |
| "Operation not permitted" | File locking conflict | ✅ Fixed (cooperative locking) |
| "Host may not exist" | Missing discovery key | Import templates correctly |
| Empty metrics | PATH issues in cron | ✅ Fixed (explicit PATH export) |

## 📚 Documentation

- **[Installation Guide](docs/INSTALLATION.md)** - Complete setup instructions
- **[Configuration Guide](docs/CONFIGURATION.md)** - Advanced configuration options
- **[Script Examples](docs/SCRIPT_EXAMPLES.md)** - Real output examples and expected behavior
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## 🎯 Use Cases

### Enterprise Virtualization
- **Data Centers**: Monitor 100+ XenServer hosts
- **Cloud Providers**: Multi-tenant monitoring
- **MSPs**: Customer environment monitoring

### Performance Optimization
- **Capacity Planning**: Historical trend analysis
- **Resource Allocation**: Real-time utilization tracking
- **Incident Response**: Automated alerting and escalation


### Development Setup
```bash
git clone https://github.com/sofus999/zabbix-xenserver-nrpe-monitoring.git
cd zabbix-xenserver-nrpe-monitoring
```
