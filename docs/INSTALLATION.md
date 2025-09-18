# Installation Guide

This guide provides step-by-step instructions for installing and configuring the Zabbix XenServer NRPE monitoring solution.

## Prerequisites

### System Requirements
- **Zabbix Server/Proxy**: 6.0 or higher
- **XenServer/Citrix Hypervisor**: 7.x or higher  
- **NRPE**: 3.x or higher
- **Operating System**: Linux (RHEL/CentOS/Ubuntu/Debian)
- **Network Access**: Port 5666 (NRPE) between Zabbix proxy and XenServer hosts

### Required Packages

#### RHEL/CentOS/Rocky Linux
```bash
# Install EPEL repository if not already installed
yum install -y epel-release

# Install required packages
yum install -y nmap jq nagios-plugins-nrpe zabbix-sender

# For older systems, you might need:
yum install -y nagios-plugins-all
```

#### Ubuntu/Debian
```bash
# Update package list
apt-get update

# Install required packages
apt-get install -y nmap jq nagios-plugins-basic zabbix-sender

# Additional plugins if needed
apt-get install -y nagios-plugins-extra
```

## Installation Steps

### Step 1: XenServer Host Configuration

This step must be performed on each XenServer host you want to monitor.

#### 1.1 Install NRPE Agent

```bash
# On XenServer host (as root)
yum install -y nrpe nagios-plugins-all

# Or download and install manually if not in repositories
wget https://github.com/NagiosEnterprises/nrpe/releases/download/nrpe-4.0.3/nrpe-4.0.3.tar.gz
tar xzf nrpe-4.0.3.tar.gz
cd nrpe-4.0.3
./configure --enable-command-args
make all
make install
```

#### 1.2 Configure NRPE

**⚠️ CRITICAL**: The `get_hostname` command is essential for discovery to work.

Create or edit NRPE configuration:

```bash
# Edit main NRPE config
vi /etc/nrpe/nrpe.cfg


Add the following configuration:

```ini
# CRITICAL: Required for host discovery
command[get_hostname]=/bin/hostname

# Host-level monitoring commands
command[check_host_load]=/usr/lib64/nagios/plugins/check_load -w 3,4,5 -c 4,5,6
command[check_host_cpu]=/usr/lib64/nagios/plugins/check_cpu.sh
command[check_host_memory]=/usr/lib64/nagios/plugins/check_memory.sh
command[check_vgpu]=/usr/lib64/nagios/plugins/check_vgpu.sh
command[check_vgpu_memory]=/usr/lib64/nagios/plugins/check_vgpu_memory.sh

# Dom0 (Control Domain) monitoring commands
command[check_load]=/usr/lib64/nagios/plugins/check_load -w 2.7,2.6,2.5 -c 3.2,3.1,3.0
command[check_cpu]=/usr/lib64/nagios/plugins/check_cpu -w 80 -c 90
command[check_memory]=/usr/lib64/nagios/plugins/check_memory -w 80 -c 90
command[check_swap]=/usr/lib64/nagios/plugins/check_swap -w 20% -c 10%
command[check_disk_root]=/usr/lib64/nagios/plugins/check_disk -w 20% -c 10% -p /
command[check_disk_log]=/usr/lib64/nagios/plugins/check_disk -w 20% -c 10% -p /var/log
command[check_xapi]=/usr/lib64/nagios/plugins/check_procs -c 1:1 -C xapi
command[check_multipath]=/usr/lib64/nagios/plugins/check_multipath.sh

# Server configuration
server_address=0.0.0.0
server_port=5666
allowed_hosts=127.0.0.1,::1,<ZABBIX_PROXY_IP>

# Security settings
dont_blame_nrpe=0
command_timeout=60
connection_timeout=300
```

**Important**: Replace `<ZABBIX_PROXY_IP>` with your actual Zabbix proxy IP address.

#### 1.3 Start and Enable NRPE Service

```bash
# Enable and start NRPE service
systemctl enable nrpe
systemctl start nrpe

# Verify service status
systemctl status nrpe

# Check if NRPE is listening
netstat -tulpn | grep :5666
ss -tulpn | grep :5666
```

#### 1.4 Configure Firewall (if enabled)

```bash
# For iptables
iptables -A INPUT -p tcp --dport 5666 -s <ZABBIX_PROXY_IP> -j ACCEPT

# For firewalld
firewall-cmd --permanent --add-port=5666/tcp --source=<ZABBIX_PROXY_IP>
firewall-cmd --reload

# For UFW (Ubuntu)
ufw allow from <ZABBIX_PROXY_IP> to any port 5666
```

#### 1.5 Test NRPE Configuration

```bash
# Test locally on XenServer host
/usr/lib64/nagios/plugins/check_nrpe -H localhost -c get_hostname

# Expected output: your hostname
```

### Step 2: Zabbix Proxy/Server Setup

#### 2.1 Clone Repository

```bash
# Clone the repository
git clone https://github.com/sofus999/zabbix-xenserver-nrpe-monitoring.git
cd zabbix-xenserver-nrpe-monitoring
```

#### 2.2 Install Dependencies

```bash
# Ensure all required packages are installed
# RHEL/CentOS
yum install -y nmap jq nagios-plugins-nrpe zabbix-sender

# Ubuntu/Debian
apt-get install -y nmap jq nagios-plugins-basic zabbix-sender
```

#### 2.3 Deploy Scripts

```bash
# Copy scripts to Zabbix external scripts directory
sudo cp Scripts/*.sh /usr/lib/zabbix/externalscripts/

# Set correct permissions
sudo chmod +x /usr/lib/zabbix/externalscripts/*.sh
sudo chown zabbix:zabbix /usr/lib/zabbix/externalscripts/*.sh

# Copy setup script
sudo cp setup_cron_jobs.sh /tmp/
sudo chmod +x /tmp/setup_cron_jobs.sh
```

#### 2.4 Test Script Connectivity

```bash
# Test NRPE connectivity from Zabbix proxy
check_nrpe -H <XENSERVER_IP> -c get_hostname

# Test discovery script manually
sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh \
    "192.168.1.0/24" --trapper --hostname "XenServer Discovery" \
    --zabbix-server <ZABBIX_SERVER_IP> --debug
```

> **💡 Expected Output**: See [Script Examples](SCRIPT_EXAMPLES.md) for detailed examples of what these commands should output when working correctly.

#### 2.5 Setup Automated Monitoring

```bash
# Run setup script with your environment configuration
sudo /tmp/setup_cron_jobs.sh \
    --zabbix-server <ZABBIX_SERVER_IP> \
    --hostname "XenServer Discovery" \
    --ip-ranges "192.168.1.0/24,10.0.0.0/24" \
    --user zabbix

# Verify cron jobs were created
sudo crontab -u zabbix -l
```

### Step 3: Zabbix Web Interface Configuration

#### 3.1 Import Templates

1. Log in to Zabbix web interface
2. Navigate to **Configuration** → **Templates**
3. Click **Import** button
4. Import templates in this order:
   - `templates/zbx_template_discover.yaml` (Discovery template)
   - `templates/zbx_template_checks.yaml` (Monitoring template)

#### 3.2 Create Discovery Host

**Option A: Import Host Configuration**
1. Navigate to **Configuration** → **Hosts**
2. Click **Import**
3. Import `templates/zbx_export_hosts.yaml`

**Option B: Manual Configuration**
1. Navigate to **Configuration** → **Hosts**
2. Click **Create host**
3. Configure:
   - **Host name**: `XenServer Discovery` (must match cron job hostname)
   - **Visible name**: `XenServer Discovery`
   - **Groups**: Create or select appropriate group
   - **Interfaces**: Add Agent interface with your Zabbix proxy IP
   - **Templates**: Link both imported templates

#### 3.3 Verify Configuration

1. Navigate to **Configuration** → **Hosts**
2. Verify the discovery host is created and enabled
3. Check **Latest data** for the discovery host
4. Look for discovery rules in **Configuration** → **Discovery**

## Verification

### Test Complete Installation

1. **Wait 5-10 minutes** for initial discovery to complete
2. Check **Configuration** → **Hosts** for newly discovered XenServer hosts
3. Verify metrics are being collected in **Monitoring** → **Latest data**
4. Check log files for any errors:

```bash
# Check discovery logs
tail -f /var/log/zabbix/xenapp_discovery.log

# Check metrics collection logs
tail -f /var/log/zabbix/xenapp_metrics.log

# Check cron execution
grep zabbix /var/log/cron
```

### Expected Results

- **Host Discovery**: XenServer hosts should appear in Zabbix hosts list
- **Metrics Discovery**: Each host should have 17 monitoring items
- **Data Collection**: All metrics should show current values
- **Scheduling**: Cron jobs should execute without errors

## Troubleshooting Installation

### Common Issues

#### NRPE Connection Refused
```bash
# Check NRPE service
systemctl status nrpe

# Check firewall
iptables -L | grep 5666
firewall-cmd --list-all

# Test connectivity
telnet <XENSERVER_IP> 5666
```

#### Permission Denied
```bash
# Fix script permissions
sudo chown zabbix:zabbix /usr/lib/zabbix/externalscripts/*.sh
sudo chmod +x /usr/lib/zabbix/externalscripts/*.sh

# Fix log directory permissions
sudo mkdir -p /var/log/zabbix
sudo chown zabbix:zabbix /var/log/zabbix
```

#### Discovery Not Working
```bash
# Test discovery manually
sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh \
    "YOUR_NETWORK/24" --trapper --hostname "XenServer Discovery" \
    --zabbix-server YOUR_ZABBIX_SERVER --debug

# Check for missing hostname command
check_nrpe -H <XENSERVER_IP> -c get_hostname
```

## Next Steps

After successful installation:

1. **Configure Alerting**: Set up triggers and notifications
2. **Create Dashboards**: Build monitoring dashboards
3. **Tune Thresholds**: Adjust warning and critical thresholds
4. **Monitor Logs**: Set up log monitoring and rotation
5. **Scale Up**: Add more XenServer environments

For detailed configuration options, see [Configuration Guide](CONFIGURATION.md).
For troubleshooting help, see [Troubleshooting Guide](TROUBLESHOOTING.md).
