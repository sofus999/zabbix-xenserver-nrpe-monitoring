# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the Zabbix XenServer NRPE monitoring solution.

## Quick Diagnostics

### Health Check Commands

Run these commands to quickly assess the system health:

> **💡 Tip**: For detailed examples of expected output, see [Script Examples](SCRIPT_EXAMPLES.md)

```bash
# 1. Test NRPE connectivity
check_nrpe -H <XENSERVER_IP> -c get_hostname

# 2. Test discovery manually
sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh \
    "192.168.1.0/24" --trapper --hostname "XenServer Discovery" \
    --zabbix-server <ZABBIX_SERVER_IP> --debug

# 3. Test metrics collection
sudo -u zabbix /usr/lib/zabbix/externalscripts/query_xen_server.sh \
    --trapper --zabbix-server <ZABBIX_SERVER_IP> --debug

# 4. Check log files
tail -f /var/log/zabbix/xenapp_*.log

# 5. Verify cron jobs
sudo crontab -u zabbix -l
```

## Common Issues and Solutions

### 1. Discovery Issues

#### No Hosts Discovered

**Symptoms:**
- Empty discovery results
- No new hosts appearing in Zabbix
- Discovery log shows "Found 0 responsive hosts"

**Diagnostic Commands:**
```bash
# Test network connectivity
nmap -p 5666 192.168.1.0/24

# Test specific host
telnet <XENSERVER_IP> 5666

# Check NRPE status on XenServer
systemctl status nrpe
```

**Common Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| NRPE not running on XenServer | `systemctl start nrpe` |
| Firewall blocking port 5666 | Configure firewall rules |
| Wrong IP range in discovery | Verify network configuration |
| Missing `get_hostname` command | Add to NRPE configuration |

**Step-by-Step Resolution:**

1. **Verify NRPE is running:**
   ```bash
   # On XenServer host
   systemctl status nrpe
   netstat -tulpn | grep :5666
   ```

2. **Test NRPE locally on XenServer:**
   ```bash
   # On XenServer host
   /usr/lib64/nagios/plugins/check_nrpe -H localhost -c get_hostname
   ```

3. **Add missing hostname command:**
   ```bash
   # On XenServer host
   echo "command[get_hostname]=/bin/hostname" >> /etc/nrpe/nrpe.cfg
   systemctl restart nrpe
   ```

4. **Test from Zabbix proxy:**
   ```bash
   # From Zabbix proxy
   check_nrpe -H <XENSERVER_IP> -c get_hostname
   ```

#### Discovery Finds Hosts But They Don't Appear in Zabbix

**Symptoms:**
- Discovery script shows "Found X responsive hosts"
- Hosts don't appear in Zabbix interface
- Zabbix shows discovery warnings

**Diagnostic Commands:**
```bash
# Check zabbix_sender output
sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh \
    "192.168.1.0/24" --trapper --hostname "XenServer Discovery" \
    --zabbix-server <ZABBIX_SERVER_IP> --debug 2>&1 | grep zabbix_sender
```

**Common Solutions:**

1. **Verify discovery host exists in Zabbix:**
   - Host name must match exactly: "XenServer Discovery"
   - Host must be enabled and monitored by proxy

2. **Check discovery key configuration:**
   ```bash
   # Verify discovery rule exists
   # In Zabbix: Configuration → Discovery → Host discovery
   ```

3. **Verify templates are imported:**
   - Import `zbx_template_discover.yaml`
   - Import `zbx_template_checks.yaml`
   - Link templates to discovery host

### 2. Metrics Collection Issues

#### Empty or Missing Metrics

**Symptoms:**
- Items show "No data" or empty values
- Latest data shows all zeros
- Graphs show no data

**Diagnostic Commands:**
```bash
# Test individual NRPE commands
check_nrpe -H <XENSERVER_IP> -c check_host_load
check_nrpe -H <XENSERVER_IP> -c check_load

# Test metrics collection manually
sudo -u zabbix /usr/lib/zabbix/externalscripts/query_xen_server.sh \
    --trapper --zabbix-server <ZABBIX_SERVER_IP> --debug
```

**Common Causes and Solutions:**

| Issue | Cause | Solution |
|-------|-------|----------|
| All metrics empty | PATH issues in cron | ✅ Fixed in scripts |
| Load averages wrong | Parsing issues | ✅ Fixed - uses performance data |
| Permission errors | File ownership | `chown zabbix:zabbix /var/log/zabbix/` |
| Cache conflicts | File locking issues | ✅ Fixed - cooperative locking |

#### Specific Metric Issues

**Load Averages Showing Same Value:**
```bash
# This is fixed - verify you have latest scripts
grep "load1=" /usr/lib/zabbix/externalscripts/query_xen_server.sh
grep "load5=" /usr/lib/zabbix/externalscripts/query_xen_server.sh
grep "load15=" /usr/lib/zabbix/externalscripts/query_xen_server.sh
```

**vGPU Metrics Showing Errors:**
```bash
# Expected for hosts without vGPU - this is normal
check_nrpe -H <XENSERVER_IP> -c check_vgpu
# Output: "UNKNOWN: Check failed ... nvidia-smi: No such file"
```

### 3. Permission and Access Issues

#### "Operation not permitted" Errors

**Symptoms:**
- Discovery script hangs asking for confirmation
- Log shows "rm: cannot remove ... Operation not permitted"
- Cache file conflicts

**Solutions:**

1. **Fix file permissions:**
   ```bash
   sudo chown zabbix:zabbix /tmp/xenapp_hosts_cache.json
   sudo chmod 644 /tmp/xenapp_hosts_cache.json
   ```

2. **Verify script ownership:**
   ```bash
   sudo chown zabbix:zabbix /usr/lib/zabbix/externalscripts/*.sh
   sudo chmod +x /usr/lib/zabbix/externalscripts/*.sh
   ```

3. **Check log directory:**
   ```bash
   sudo mkdir -p /var/log/zabbix
   sudo chown zabbix:zabbix /var/log/zabbix
   sudo chmod 755 /var/log/zabbix
   ```

#### "Root privileges required" Error

**Symptoms:**
- nmap fails with "You requested a scan type which requires root privileges"
- Discovery finds 0 hosts

**Solution:**
This is fixed in the current scripts. Verify you have the latest version:

```bash
# Check scan type in script
grep "\-sT" /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh
# Should show: nmap -n -sT -p 5666 ...
```

If you see `-sS`, update to the latest script version.

### 4. Cron and Scheduling Issues

#### Cron Jobs Not Running

**Symptoms:**
- No log files created
- Discovery never runs automatically
- Metrics not collected

**Diagnostic Commands:**
```bash
# Check if cron jobs exist
sudo crontab -u zabbix -l

# Check cron service
systemctl status cron
# or
systemctl status crond

# Check cron logs
grep zabbix /var/log/cron
tail -f /var/log/cron
```

**Solutions:**

1. **Verify cron service is running:**
   ```bash
   sudo systemctl enable cron
   sudo systemctl start cron
   ```

2. **Check cron job syntax:**
   ```bash
   # Verify proper cron format
   sudo crontab -u zabbix -l
   ```

3. **Test cron job manually:**
   ```bash
   # Run as zabbix user
   sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh \
       "192.168.1.0/24" --trapper --hostname "XenServer Discovery" \
       --zabbix-server <ZABBIX_SERVER_IP>
   ```

#### Scripts Run but No Output

**Symptoms:**
- Cron jobs execute (visible in cron log)
- No log files created
- No errors visible

**Solutions:**

1. **Check PATH issues:**
   ```bash
   # Test with restricted PATH (simulates cron environment)
   sudo -u zabbix env -i PATH=/usr/bin:/bin \
       /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh \
       "192.168.1.0/24" --trapper --hostname "XenServer Discovery" \
       --zabbix-server <ZABBIX_SERVER_IP>
   ```

2. **Verify log redirection:**
   ```bash
   # Check if log files are being created
   ls -la /var/log/zabbix/
   
   # Test manual redirection
   echo "test" >> /var/log/zabbix/xenapp_discovery.log
   ```

### 5. Network and Connectivity Issues

#### Intermittent Connection Failures

**Symptoms:**
- Some hosts discovered, others missing
- Metrics collection fails randomly
- Connection timeouts in logs

**Diagnostic Commands:**
```bash
# Test network stability
ping -c 10 <XENSERVER_IP>

# Test NRPE connection stability
for i in {1..10}; do
    echo "Test $i:"
    check_nrpe -H <XENSERVER_IP> -c get_hostname
    sleep 1
done
```

**Solutions:**

1. **Increase timeouts:**
   ```bash
   # Edit NRPE configuration
   # /etc/nrpe/nrpe.cfg
   command_timeout=60
   connection_timeout=300
   ```

2. **Optimize nmap timing:**
   ```bash
   # Current optimized settings:
   nmap -n -sT -p 5666 -T5 --max-retries 1 --host-timeout 5s
   ```

3. **Check network configuration:**
   ```bash
   # Verify routing
   traceroute <XENSERVER_IP>
   
   # Check for packet loss
   mtr -r -c 10 <XENSERVER_IP>
   ```

### 6. Zabbix Server Issues

#### Templates Not Working

**Symptoms:**
- Discovery hosts created but no items
- Items exist but show "Not supported"
- Trigger warnings about missing items

**Solutions:**

1. **Verify template import order:**
   ```
   1. zbx_template_discover.yaml (Discovery template)
   2. zbx_template_checks.yaml (Monitoring template)
   3. zbx_export_hosts.yaml (Host configuration)
   ```

2. **Check template linkage:**
   - Configuration → Hosts → [Discovery Host] → Templates
   - Verify both templates are linked

3. **Validate discovery rules:**
   - Configuration → Discovery
   - Check "xenapp.host.discovery" and "xenapp.metrics.discovery" rules

#### Discovery Rules Not Triggering

**Symptoms:**
- Manual discovery works
- Automatic discovery doesn't create hosts
- Discovery rules show "Never" for last check

**Solutions:**

1. **Check discovery rule configuration:**
   ```
   Update interval: 1d (86400)
   Keep lost resources: 30d
   Check discovery rule: Enabled
   ```

2. **Force discovery rule execution:**
   - Configuration → Discovery → [Rule] → Execute now

3. **Check Zabbix server logs:**
   ```bash
   tail -f /var/log/zabbix/zabbix_server.log | grep discovery
   ```

### 7. Performance Issues

#### Slow Discovery

**Symptoms:**
- Discovery takes very long time
- nmap scans timeout
- High CPU usage during discovery

**Solutions:**

1. **Optimize network ranges:**
   ```bash
   # Split large networks
   --ip-ranges "192.168.1.0/26,192.168.1.64/26"
   # Instead of:
   --ip-ranges "192.168.1.0/24"
   ```

2. **Adjust scan timing:**
   ```bash
   # Current optimized settings
   nmap -n -sT -p 5666 -T5 --max-retries 1 --host-timeout 5s
   ```

3. **Schedule discovery during off-hours:**
   ```bash
   # Run at 2 AM instead of 6 AM
   0 2 * * * discovery_script...
   ```

## Advanced Debugging

### Enable Full Debug Logging

1. **Script-level debugging:**
   ```bash
   # Add debug flag to cron jobs temporarily
   * * * * * /usr/lib/zabbix/externalscripts/query_xen_server.sh \
       --trapper --zabbix-server <SERVER> --debug >> /var/log/zabbix/debug.log 2>&1
   ```

2. **Zabbix server debugging:**
   ```bash
   # Edit zabbix_server.conf
   DebugLevel=4
   LogFile=/var/log/zabbix/zabbix_server.log
   ```

3. **NRPE debugging:**
   ```bash
   # Edit nrpe.cfg
   debug=1
   ```

### Log Analysis

```bash
# Monitor all logs simultaneously
tail -f /var/log/zabbix/*.log

# Search for errors
grep -i error /var/log/zabbix/*.log

# Check for specific issues
grep -i "permission\|denied\|failed" /var/log/zabbix/*.log
```

### Network Analysis

```bash
# Monitor NRPE traffic
tcpdump -i any port 5666

# Check Zabbix communication
tcpdump -i any port 10051

# Monitor DNS resolution
tcpdump -i any port 53
```

## Getting Help

### Before Seeking Support

1. **Collect diagnostic information:**
   ```bash
   # Create support bundle
   mkdir /tmp/zabbix-debug
   cp /var/log/zabbix/*.log /tmp/zabbix-debug/
   sudo crontab -u zabbix -l > /tmp/zabbix-debug/crontab.txt
   ls -la /usr/lib/zabbix/externalscripts/ > /tmp/zabbix-debug.txt
   tar czf zabbix-xenserver-debug.tar.gz /tmp/zabbix-debug/
   ```

2. **Document your environment:**
   - Zabbix version
   - XenServer version
   - Network topology
   - Number of hosts

3. **Include error messages:**
   - Exact error text
   - Log entries with timestamps
   - Configuration snippets

### Support Channels

1. **GitHub Issues**: [Create an issue](https://github.com/sofus999/zabbix-xenserver-nrpe-monitoring/issues)
2. **Zabbix Community**: [Zabbix Forums](https://www.zabbix.com/forum)
3. **Documentation**: Review all documentation files in this repository

### Contributing Fixes

If you resolve an issue:

1. **Document the solution** in this troubleshooting guide
2. **Submit a pull request** with fixes
3. **Share your experience** to help others

---

**Remember**: Most issues are related to network connectivity, permissions, or configuration. Start with the basics and work systematically through the diagnostic steps.
