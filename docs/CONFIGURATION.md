# Configuration Guide

This guide covers advanced configuration options for the Zabbix XenServer NRPE monitoring solution.

## Template Configuration

### Macro Customization

The monitoring solution uses Zabbix macros for flexible threshold management. You can customize these at the template, host group, or individual host level.

#### Global Thresholds

Navigate to **Configuration** → **Templates** → **[Template Name]** → **Macros**

| Macro | Default Value | Description |
|-------|---------------|-------------|
| `{$HIGH_THRESHOLD}` | 90 | Global critical threshold (%) |
| `{$WARN_THRESHOLD}` | 80 | Global warning threshold (%) |

#### Load Average Thresholds

| Macro | Default Value | Description |
|-------|---------------|-------------|
| `{$HIGH_THRESHOLD:"dom0.load"}` | 3.2 | Dom0 load critical threshold |
| `{$WARN_THRESHOLD:"dom0.load"}` | 2.7 | Dom0 load warning threshold |
| `{$HIGH_THRESHOLD:"host.load"}` | 4 | Host load critical threshold |
| `{$WARN_THRESHOLD:"host.load"}` | 3 | Host load warning threshold |

#### Memory and CPU Thresholds

| Macro | Default Value | Description |
|-------|---------------|-------------|
| `{$HIGH_THRESHOLD:"cpu"}` | 90 | CPU critical threshold (%) |
| `{$WARN_THRESHOLD:"cpu"}` | 80 | CPU warning threshold (%) |
| `{$HIGH_THRESHOLD:"memory"}` | 90 | Memory critical threshold (%) |
| `{$WARN_THRESHOLD:"memory"}` | 80 | Memory warning threshold (%) |

### Discovery Rule Configuration

#### Host Discovery Settings

**Discovery Rule**: `xenapp.host.discovery`
- **Type**: Zabbix trapper (data pushed via external scripts)
- **Update interval**: 0 (not applicable for trapper items)
- **Keep lost resources**: 30 days
- **Discovery frequency**: Daily at 06:00 (controlled by cron job)

#### Metrics Discovery Settings

**Discovery Rule**: `xenapp.metrics.discovery`
- **Type**: Zabbix trapper (data pushed via external scripts)
- **Update interval**: 0 (not applicable for trapper items)
- **Keep lost resources**: 7 days
- **Discovery frequency**: Daily at 06:05 (controlled by cron job)

### Trapper vs Polled Items

**Important**: This solution uses **Zabbix trapper** items, which means:
- Data is **pushed** to Zabbix via `zabbix_sender` from external scripts
- Zabbix does **not poll** the items on a schedule
- Update intervals in discovery rules are set to `0` (not applicable)
- Data collection frequency is controlled by **cron jobs**, not Zabbix intervals

### Item Prototypes

Each discovered host automatically gets 17 monitoring items (all trapper type):

#### Host Metrics
- `nrpe.[host.load]` - 1-minute load average
- `nrpe.[host.cpu]` - CPU utilization
- `nrpe.[host.memory]` - Memory utilization
- `nrpe.[host.vgpu]` - vGPU utilization
- `nrpe.[host.vgpu_memory]` - vGPU memory usage

#### Dom0 Metrics
- `nrpe.[dom0.load.1min]` - Dom0 1-minute load
- `nrpe.[dom0.load.5min]` - Dom0 5-minute load
- `nrpe.[dom0.load.15min]` - Dom0 15-minute load
- `nrpe.[dom0.cpu]` - Dom0 CPU utilization
- `nrpe.[dom0.memory]` - Dom0 memory utilization
- `nrpe.[dom0.swap]` - Dom0 swap utilization
- `nrpe.[dom0.disk.root]` - Root partition usage
- `nrpe.[dom0.disk.log]` - Log partition usage
- `nrpe.[xapi.status]` - XAPI service status
- `nrpe.[multipath.status]` - Multipath status

## Script Configuration

### Discovery Scripts

#### Host Discovery Script Configuration

Edit `/usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh`:

```bash
# Cache file location
CACHE_FILE="/tmp/xenapp_hosts_cache.json"
CACHE_LOCK="/tmp/xenapp_hosts_cache.lock"

# Default Zabbix connection settings
ZABBIX_SERVER=""
ZABBIX_PORT="10051"
ZABBIX_HOSTNAME=""
DISCOVERY_KEY="xenapp.host.discovery"
```

#### Metrics Discovery Script Configuration

Edit `/usr/lib/zabbix/externalscripts/discover_xenapp_metrics.sh`:

```bash
# Cache file location
CACHE_FILE="/tmp/xenapp_hosts_cache.json"

# Default Zabbix connection settings
ZABBIX_SERVER="127.0.0.1"
ZABBIX_PORT="10051"
DISCOVERY_KEY="xenapp.metrics.discovery"
```

#### Metrics Collection Script Configuration

Edit `/usr/lib/zabbix/externalscripts/query_xen_server.sh`:

```bash
# Cache file location
CACHE_FILE="/tmp/xenapp_hosts_cache.json"
CACHE_LOCK="/tmp/xenapp_hosts_cache.lock"

# Default Zabbix connection settings
ZABBIX_SERVER=""
ZABBIX_PORT="10051"
```

### Network Scanning Configuration

#### Scan Timing Options

The discovery script uses nmap with optimized settings:

```bash
# Current settings (in discover_xenapp_hosts.sh)
nmap -n -sT -p 5666 -T5 --max-retries 1 --host-timeout 5s -oG - --open $SCAN_TARGETS

# Options explanation:
# -n              : No DNS resolution (faster)
# -sT             : TCP connect scan (no root required)
# -p 5666         : Only scan NRPE port
# -T5             : Aggressive timing (fastest)
# --max-retries 1 : Only retry once
# --host-timeout 5s : 5 second timeout per host
```

#### Custom Network Ranges

You can configure multiple network ranges in the cron setup:

```bash
# Single network
--ip-ranges "192.168.1.0/24"

# Multiple networks
--ip-ranges "192.168.1.0/24,10.0.0.0/24,172.16.0.0/16"

# Individual IPs mixed with ranges
--ip-ranges "192.168.1.0/24,10.0.0.100,172.16.1.0/24"
```

## Understanding Trapper Architecture

### Why Trapper Items?

This monitoring solution uses **Zabbix trapper** items instead of traditional polled items for several reasons:

1. **Reduced NRPE Load**: Instead of Zabbix making individual NRPE calls for each metric, we batch all checks into a single script execution
2. **Better Performance**: One script execution per host per minute vs. 17 individual NRPE calls
3. **Centralized Control**: Data collection timing controlled by cron, not distributed across multiple Zabbix processes
4. **Cache Coordination**: Scripts can share host discovery cache and implement file locking

### Key Differences

| Aspect | Traditional NRPE | Our Trapper Solution |
|--------|------------------|---------------------|
| **Data Flow** | Zabbix polls → NRPE | Script pushes → Zabbix |
| **Intervals** | Set in Zabbix items | Set in cron jobs |
| **NRPE Calls** | 17 calls per host | 1 call per host |
| **Performance** | Higher NRPE load | Optimized batch processing |
| **Coordination** | Independent items | Shared cache and locking |

### Template Configuration Impact

- **Discovery Rules**: `delay: '0'` (not polled by Zabbix)
- **Item Prototypes**: `type: DEPENDENT` (inherit from master item)
- **Master Item**: `type: TRAP` with `delay: '0'`
- **Data Source**: External scripts via `zabbix_sender`

## Cron Configuration

### Schedule Customization

Edit the cron schedule by modifying `/tmp/setup_cron_jobs.sh` or manually editing crontab:

```bash
# View current cron jobs
sudo crontab -u zabbix -l

# Edit cron jobs
sudo crontab -u zabbix -e
```

#### Default Schedule
```bash
# Host Discovery - Daily at 06:00
0 6 * * * /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh

# Metrics Discovery - Daily at 06:05  
5 6 * * * /usr/lib/zabbix/externalscripts/discover_xenapp_metrics.sh

# Metrics Collection - Every minute
* * * * * /usr/lib/zabbix/externalscripts/query_xen_server.sh
```

#### Alternative Schedules

**High-Frequency Discovery** (for dynamic environments):
```bash
# Host Discovery - Every 4 hours
0 */4 * * * /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh

# Metrics Discovery - Every 4 hours (5 minutes after host discovery)
5 */4 * * * /usr/lib/zabbix/externalscripts/discover_xenapp_metrics.sh
```

**Low-Frequency Discovery** (for stable environments):
```bash
# Host Discovery - Weekly on Sundays at 02:00
0 2 * * 0 /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh

# Metrics Discovery - Weekly on Sundays at 02:05
5 2 * * 0 /usr/lib/zabbix/externalscripts/discover_xenapp_metrics.sh
```

### Environment Variables

You can set environment variables for the scripts:

```bash
# Example cron entry with environment variables
0 6 * * * ZABBIX_SERVER=192.168.1.100 DEBUG=1 /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh "192.168.1.0/24" --trapper
```

## Logging Configuration

### Log Levels

The scripts support different log levels through debug mode:

```bash
# Normal mode - essential messages only
/usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh --trapper

# Debug mode - verbose output
/usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh --trapper --debug
```

### Log Rotation

The setup script configures logrotate automatically. You can customize it by editing `/etc/logrotate.d/xenapp-monitoring`:

```bash
/var/log/zabbix/xenapp_discovery.log
/var/log/zabbix/xenapp_metrics_discovery.log
/var/log/zabbix/xenapp_metrics.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    dateext
    dateformat _%d_%m_%y
    create 644 zabbix zabbix
    postrotate
        chown zabbix:zabbix /var/log/zabbix/xenapp_*.log 2>/dev/null || true
    endscript
}
```

#### Custom Log Rotation Options

**Daily rotation with 30-day retention**:
```bash
/var/log/zabbix/xenapp_*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 644 zabbix zabbix
}
```

**Size-based rotation**:
```bash
/var/log/zabbix/xenapp_*.log {
    size 100M
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 644 zabbix zabbix
}
```

## NRPE Configuration Customization

### Custom Check Commands

You can add custom monitoring commands to your NRPE configuration:

#### Storage Monitoring
```ini
# Additional storage checks
command[check_disk_var]=/usr/lib64/nagios/plugins/check_disk -w 20% -c 10% -p /var
command[check_disk_tmp]=/usr/lib64/nagios/plugins/check_disk -w 20% -c 10% -p /tmp
command[check_disk_home]=/usr/lib64/nagios/plugins/check_disk -w 20% -c 10% -p /home
```

#### Network Monitoring
```ini
# Network interface checks
command[check_network_eth0]=/usr/lib64/nagios/plugins/check_network.sh eth0
command[check_network_xenbr0]=/usr/lib64/nagios/plugins/check_network.sh xenbr0
```

#### Service Monitoring
```ini
# Additional service checks
command[check_ntpd]=/usr/lib64/nagios/plugins/check_procs -c 1:1 -C ntpd
command[check_sshd]=/usr/lib64/nagios/plugins/check_procs -c 1: -C sshd
command[check_xenopsd]=/usr/lib64/nagios/plugins/check_procs -c 1:1 -C xenopsd
```

### Security Configuration

#### SSL/TLS Configuration
```ini
# Enable SSL
ssl_logging=1
ssl_version=TLSv1.2+
ssl_cert_file=/etc/pki/nrpe/server-cert.pem
ssl_privatekey_file=/etc/pki/nrpe/server-key.pem
ssl_cacert_file=/etc/pki/nrpe/ca-cert.pem
ssl_client_certs=0
```

#### Access Control
```ini
# Restrict access to specific IPs
allowed_hosts=127.0.0.1,::1,192.168.1.100,192.168.1.101

# Disable command arguments for security
dont_blame_nrpe=0

# Set timeouts
command_timeout=60
connection_timeout=300
```

## Performance Tuning

### Large Environment Optimization

For environments with 50+ XenServer hosts:

#### Script Timeouts
```bash
# Increase timeouts in scripts
export NRPE_TIMEOUT=30
export ZABBIX_TIMEOUT=60
export DISCOVERY_TIMEOUT=300
```

#### Parallel Processing
```bash
# Split large networks into smaller chunks
--ip-ranges "192.168.1.0/26,192.168.1.64/26,192.168.1.128/26,192.168.1.192/26"
```

#### Zabbix Server Configuration

Optimize Zabbix server for large environments:

```ini
# zabbix_server.conf
StartPollers=100
StartTrappers=20
StartPingers=10
CacheSize=128M
HistoryCacheSize=64M
TrendCacheSize=32M
ValueCacheSize=256M
```

### Database Optimization

For MySQL/MariaDB:

```sql
-- Optimize for monitoring workload
SET GLOBAL innodb_buffer_pool_size = 2147483648;  -- 2GB
SET GLOBAL max_connections = 200;
SET GLOBAL innodb_flush_log_at_trx_commit = 2;
```

## Advanced Features

### Multi-Site Configuration

For monitoring multiple data centers:

1. **Deploy separate Zabbix proxies** at each site
2. **Configure site-specific IP ranges**:
   ```bash
   # Site A
   ./setup_cron_jobs.sh --ip-ranges "10.1.0.0/16" --hostname "XenServer Discovery Site A"
   
   # Site B  
   ./setup_cron_jobs.sh --ip-ranges "10.2.0.0/16" --hostname "XenServer Discovery Site B"
   ```

3. **Use site-specific host groups** in Zabbix

### Integration with External Systems

#### Slack Notifications
```bash
# Add to trigger actions
/usr/local/bin/zabbix-slack.sh "{ALERT.SUBJECT}" "{ALERT.MESSAGE}"
```

#### Email Integration
```bash
# Configure in Zabbix media types
/usr/lib/zabbix/alertscripts/sendmail.sh "{ALERT.SENDTO}" "{ALERT.SUBJECT}" "{ALERT.MESSAGE}"
```

#### SNMP Trap Integration
```bash
# Send SNMP traps for critical events
snmptrap -v2c -c public monitoring-server 1.3.6.1.4.1.12345 "" 6 1 1.3.6.1.4.1.12345.1 s "{ALERT.MESSAGE}"
```

## Troubleshooting Configuration

### Debug Mode

Enable debug mode for troubleshooting:

```bash
# Test discovery with debug output
sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh \
    "192.168.1.0/24" --trapper --hostname "XenServer Discovery" \
    --zabbix-server 192.168.1.100 --debug

# Test metrics collection with debug
sudo -u zabbix /usr/lib/zabbix/externalscripts/query_xen_server.sh \
    --trapper --zabbix-server 192.168.1.100 --debug
```

### Configuration Validation

```bash
# Test NRPE configuration
/usr/lib64/nagios/plugins/check_nrpe -H localhost -c get_hostname

# Validate Zabbix sender
echo "test.item 1" | zabbix_sender -z zabbix-server -s test-host -i -

# Check file permissions
ls -la /usr/lib/zabbix/externalscripts/
ls -la /var/log/zabbix/
```

For more troubleshooting information, see the [Troubleshooting Guide](TROUBLESHOOTING.md).
