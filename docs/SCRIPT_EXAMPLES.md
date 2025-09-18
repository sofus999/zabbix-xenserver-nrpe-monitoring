# Script Output Examples

This document provides real examples of script output to help you understand what to expect when the monitoring solution is working correctly.

## 🔍 Host Discovery Script Output

### Command
```bash
sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_hosts.sh "192.168.1.0/24" --trapper --hostname "XenServer Discovery" --zabbix-server 192.168.1.100 --debug
```

### Expected Output
```
[2025-09-18 12:30:35] Starting discovery in trapper mode
[2025-09-18 12:30:35] Scanning targets: 192.168.1.0/24
[2025-09-18 12:30:37] Found 25 responsive hosts
[2025-09-18 12:30:37] Processing host: 192.168.1.71
[2025-09-18 12:30:37] Host 192.168.1.71 (xenserver-host-013) marked as active
[2025-09-18 12:30:37] Processing host: 192.168.1.72
[2025-09-18 12:30:37] Host 192.168.1.72 (xenserver-host-014) marked as active
[2025-09-18 12:30:37] Processing host: 192.168.1.73
[2025-09-18 12:30:37] Host 192.168.1.73 (xenserver-host-015) marked as active
[2025-09-18 12:30:37] Processing host: 192.168.1.84
[2025-09-18 12:30:38] Host 192.168.1.84 (xenserver-host-001) marked as active
[2025-09-18 12:30:38] Processing host: 192.168.1.87
[2025-09-18 12:30:38] Host 192.168.1.87 (xenserver-host-002) marked as active
[2025-09-18 12:30:38] Processing host: 192.168.1.88
[2025-09-18 12:30:38] Host 192.168.1.88 (xenserver-host-003) marked as active
[... additional hosts ...]
[2025-09-18 12:30:42] Cache updated with 25 hosts
[2025-09-18 12:30:42] [DEBUG] Sending to zabbix_sender:
[2025-09-18 12:30:42] [DEBUG] Host: XenServer Discovery
[2025-09-18 12:30:42] [DEBUG] Key: xenapp.host.discovery
[2025-09-18 12:30:42] [DEBUG] Data: {
  "data": [
    {
      "{#HOST.IP}": "192.168.1.71",
      "{#HOST.NAME}": "xenserver-host-013"
    },
    {
      "{#HOST.IP}": "192.168.1.72",
      "{#HOST.NAME}": "xenserver-host-014"
    },
    {
      "{#HOST.IP}": "192.168.1.73",
      "{#HOST.NAME}": "xenserver-host-015"
    }
    ... additional host entries ...
  ]
}
[2025-09-18 12:30:42] [DEBUG] Using zabbix_agent2.conf config file
Response from "192.168.1.100:10051": "processed: 1; failed: 0; total: 1; seconds spent: 0.000062"
sent: 1; skipped: 0; total: 1
[2025-09-18 12:30:42] Discovery data sent to Zabbix server 192.168.1.100:10051
[2025-09-18 12:30:42] Discovery completed successfully
```

### Key Indicators of Success
- ✅ **Found X responsive hosts** - Shows network scanning worked
- ✅ **Host marked as active** - Hostname retrieval successful
- ✅ **Cache updated** - Local cache file updated
- ✅ **processed: 1; failed: 0** - Zabbix accepted the discovery data
- ✅ **Discovery completed successfully** - Full process completed

## 📊 Metrics Discovery Script Output

### Command
```bash
sudo -u zabbix /usr/lib/zabbix/externalscripts/discover_xenapp_metrics.sh --trapper --zabbix-server 192.168.1.100
```

### Expected Output
```
[2025-09-18 12:31:02] Starting metrics discovery in trapper mode
[2025-09-18 12:31:02] Metrics discovery sent successfully for host xenserver-host-013
[2025-09-18 12:31:02] Metrics discovery sent successfully for host xenserver-host-014
[2025-09-18 12:31:02] Metrics discovery sent successfully for host xenserver-host-015
[2025-09-18 12:31:02] Metrics discovery sent successfully for host xenserver-host-001
[2025-09-18 12:31:02] Metrics discovery sent successfully for host xenserver-host-002
[2025-09-18 12:31:02] Metrics discovery sent successfully for host xenserver-host-003
[2025-09-18 12:31:02] Metrics discovery sent successfully for host xenserver-host-005
[... additional hosts ...]
[2025-09-18 12:31:02] Metrics discovery completed: 25 succeeded, 0 pending (hosts may not exist yet)
```

### Key Indicators of Success
- ✅ **Metrics discovery sent successfully** - Each host gets 17 monitoring items
- ✅ **X succeeded, 0 pending** - All hosts processed without errors
- ✅ **Starting metrics discovery in trapper mode** - Correct operational mode

## 🔄 Metrics Collection Script Output

### Command
```bash
sudo -u zabbix /usr/lib/zabbix/externalscripts/query_xen_server.sh --trapper --zabbix-server 192.168.1.100 --debug
```

### Expected Output (Sample Host)
```
[2025-09-18 12:31:11] Starting metrics collection in trapper mode
[2025-09-18 12:31:11] [DEBUG] Loading hosts from cache...
[2025-09-18 12:31:11] [DEBUG] Total hosts loaded: 25
[2025-09-18 12:31:11] [DEBUG] First 5 hosts:
[2025-09-18 12:31:11] [DEBUG]   192.168.1.71:xenserver-host-013
[2025-09-18 12:31:11] [DEBUG]   192.168.1.72:xenserver-host-014
[2025-09-18 12:31:11] [DEBUG]   192.168.1.73:xenserver-host-015
[2025-09-18 12:31:11] [DEBUG]   192.168.1.84:xenserver-host-001
[2025-09-18 12:31:11] [DEBUG]   192.168.1.87:xenserver-host-002
[2025-09-18 12:31:11] [DEBUG] Processing host 1/25: 192.168.1.71 (xenserver-host-013)

[2025-09-18 12:31:12] [DEBUG] ----------------------------------
[2025-09-18 12:31:12] [DEBUG] Processing metric: host.load for host 192.168.1.71
[2025-09-18 12:31:12] [DEBUG]  -> NRPE Command:  check_nrpe -H 192.168.1.71 -c check_host_load
[2025-09-18 12:31:12] [DEBUG]  -> Raw Output:    'OK - load average per CPU: 0.47 | load=0.47;3;4;0'
[2025-09-18 12:31:12] [DEBUG]  -> Exit Code:     0
[2025-09-18 12:31:12] [DEBUG]  -> Parsed Value:  '0.47'

[2025-09-18 12:31:12] [DEBUG] ----------------------------------
[2025-09-18 12:31:12] [DEBUG] Processing metric: host.cpu for host 192.168.1.71
[2025-09-18 12:31:13] [DEBUG]  -> NRPE Command:  check_nrpe -H 192.168.1.71 -c check_host_cpu
[2025-09-18 12:31:13] [DEBUG]  -> Raw Output:    'OK - free host CPU: 89.66% | usage=10.34%;80;90;0;100'
[2025-09-18 12:31:13] [DEBUG]  -> Exit Code:     0
[2025-09-18 12:31:13] [DEBUG]  -> Parsed Value:  '10.34'

[2025-09-18 12:31:13] [DEBUG] ----------------------------------
[2025-09-18 12:31:13] [DEBUG] Processing metric: host.memory for host 192.168.1.71
[2025-09-18 12:31:13] [DEBUG]  -> NRPE Command:  check_nrpe -H 192.168.1.71 -c check_host_memory
[2025-09-18 12:31:13] [DEBUG]  -> Raw Output:    'OK - free host memory: 61.11% | usage=38.89%;80;90;0;100'
[2025-09-18 12:31:13] [DEBUG]  -> Exit Code:     0
[2025-09-18 12:31:14] [DEBUG]  -> Parsed Value:  '38.89'

[2025-09-18 12:31:14] [DEBUG] ----------------------------------
[2025-09-18 12:31:14] [DEBUG] Processing metric: host.vgpu for host 192.168.1.71
[2025-09-18 12:31:14] [DEBUG]  -> NRPE Command:  check_nrpe -H 192.168.1.71 -c check_vgpu
[2025-09-18 12:31:14] [DEBUG]  -> Raw Output:    'UNKNOWN: Check failed - nvidia-smi: No such file or directory'
[2025-09-18 12:31:14] [DEBUG]  -> Exit Code:     0
[2025-09-18 12:31:14] [DEBUG]  -> Parsed Value:  'UNKNOWN: Check failed - nvidia-smi: No such file or directory'

[2025-09-18 12:31:15] [DEBUG] ----------------------------------
[2025-09-18 12:31:15] [DEBUG] Processing metric: dom0.load.1min for host 192.168.1.71
[2025-09-18 12:31:15] [DEBUG]  -> NRPE Command:  check_nrpe -H 192.168.1.71 -c check_load
[2025-09-18 12:31:15] [DEBUG]  -> Raw Output:    'OK - load average per CPU: 0.02, 0.02, 0.02|load1=0.023;2.700;3.200;0; load5=0.020;2.600;3.100;0; load15=0.019;2.500;3.000;0;'
[2025-09-18 12:31:15] [DEBUG]  -> Exit Code:     0
[2025-09-18 12:31:15] [DEBUG]  -> Parsed Value:  '0.023'

[2025-09-18 12:31:15] [DEBUG] ----------------------------------
[2025-09-18 12:31:15] [DEBUG] Processing metric: dom0.load.5min for host 192.168.1.71
[2025-09-18 12:31:16] [DEBUG]  -> NRPE Command:  check_nrpe -H 192.168.1.71 -c check_load
[2025-09-18 12:31:16] [DEBUG]  -> Raw Output:    'OK - load average per CPU: 0.02, 0.02, 0.02|load1=0.023;2.700;3.200;0; load5=0.020;2.600;3.100;0; load15=0.019;2.500;3.000;0;'
[2025-09-18 12:31:16] [DEBUG]  -> Exit Code:     0
[2025-09-18 12:31:16] [DEBUG]  -> Parsed Value:  '0.020'

[2025-09-18 12:31:16] [DEBUG] ----------------------------------
[2025-09-18 12:31:16] [DEBUG] Processing metric: dom0.load.15min for host 192.168.1.71
[2025-09-18 12:31:16] [DEBUG]  -> NRPE Command:  check_nrpe -H 192.168.1.71 -c check_load
[2025-09-18 12:31:16] [DEBUG]  -> Raw Output:    'OK - load average per CPU: 0.02, 0.02, 0.02|load1=0.023;2.700;3.200;0; load5=0.020;2.600;3.100;0; load15=0.019;2.500;3.000;0;'
[2025-09-18 12:31:16] [DEBUG]  -> Exit Code:     0
[2025-09-18 12:31:16] [DEBUG]  -> Parsed Value:  '0.019'

[2025-09-18 12:31:21] [DEBUG] Sending master item to Zabbix server 192.168.1.100:10051
[2025-09-18 12:31:21] [DEBUG] Host: xenserver-host-013, Key: nrpe.master.data
[2025-09-18 12:31:21] [DEBUG] Master item sent successfully for host xenserver-host-013
[2025-09-18 12:31:21] [DEBUG] Completed host 1/25, moving to next...
```

### Key Indicators of Success
- ✅ **Total hosts loaded: X** - Cache file read successfully
- ✅ **Processing host X/Y** - Iterating through all discovered hosts
- ✅ **Exit Code: 0** - NRPE commands executing successfully
- ✅ **Parsed Value: 'X.XX'** - Metrics being extracted correctly
- ✅ **Different values for load1/load5/load15** - Load average parsing working correctly
- ✅ **Master item sent successfully** - Data pushed to Zabbix successfully

### Understanding vGPU Errors (Normal Behavior)
```
[DEBUG]  -> Raw Output: 'UNKNOWN: Check failed - nvidia-smi: No such file or directory'
[DEBUG]  -> Parsed Value: 'UNKNOWN: Check failed - nvidia-smi: No such file or directory'
```
This is **expected behavior** for hosts without vGPU hardware. The monitoring solution handles this gracefully.

## 🔧 Individual NRPE Check Examples

### Hostname Check (Critical for Discovery)
```bash
$ check_nrpe -H 192.168.1.71 -c get_hostname
xenserver-host-013
```

### Load Average Check (Shows Fixed Parsing)
```bash
$ check_nrpe -H 192.168.1.71 -c check_load
OK - load average per CPU: 0.02, 0.02, 0.02|load1=0.023;2.700;3.200;0; load5=0.020;2.600;3.100;0; load15=0.019;2.500;3.000;0;
```
**Note**: The script correctly extracts different values:
- 1min: `0.023` (from `load1=0.023`)
- 5min: `0.020` (from `load5=0.020`) 
- 15min: `0.019` (from `load15=0.019`)

### Host Load Check
```bash
$ check_nrpe -H 192.168.1.71 -c check_host_load
OK - load average per CPU: 0.47 | load=0.47;3;4;0
```

### CPU Utilization Check
```bash
$ check_nrpe -H 192.168.1.71 -c check_host_cpu
OK - free host CPU: 89.66% | usage=10.34%;80;90;0;100
```

### Memory Utilization Check
```bash
$ check_nrpe -H 192.168.1.71 -c check_host_memory
OK - free host memory: 61.11% | usage=38.89%;80;90;0;100
```

### Disk Usage Check
```bash
$ check_nrpe -H 192.168.1.71 -c check_disk_root
DISK OK - free space: / 14751 MiB (86.52% inode=92%);| /=2297MiB;14376;16173;0;17970
```

### Service Status Check
```bash
$ check_nrpe -H 192.168.1.71 -c check_xapi
OK - xapi is running | uptime=1395247s
```

## 📋 Final JSON Data Structure

The metrics collection script generates this JSON structure for each host:

```json
{
  "host.load": "0.47",
  "host.cpu": "10.34",
  "host.memory": "38.89",
  "host.vgpu": "UNKNOWN: Check failed - nvidia-smi: No such file or directory",
  "host.vgpu_memory": "UNKNOWN: Check failed - nvidia-smi: No such file or directory",
  "dom0.load.1min": "0.023",
  "dom0.load.5min": "0.020",
  "dom0.load.15min": "0.019",
  "dom0.cpu": "1.32",
  "dom0.memory": "14.72",
  "dom0.swap": "0",
  "dom0.disk.root": "14",
  "dom0.disk.log": "7",
  "xapi.status": "1",
  "multipath.status": "UNKNOWN: Multipath is not enabled"
}
```

## 🎯 Performance Highlights

From the debug output, you can see the solution's efficiency:

- **Network Discovery**: Scans entire `/24` network and finds 25 hosts in ~2 seconds
- **Batch Processing**: All 17 metrics collected per host in ~10 seconds via single script execution
- **Load Average Parsing**: Successfully extracts different 1min/5min/15min values from performance data
- **Error Handling**: Gracefully handles missing features (vGPU, multipath) without failing
- **Cache Management**: Persistent storage and coordinated access between scripts

## 🚨 Troubleshooting Indicators

### Common Error Patterns

**No hosts found:**
```
[2025-09-18 12:30:37] Found 0 responsive hosts
```

**NRPE connection issues:**
```
[DEBUG]  -> Raw Output: 'CHECK_NRPE: Error - Could not complete SSL handshake.'
[DEBUG]  -> Exit Code: 2
```

**Missing hostname command:**
```
[DEBUG]  -> Raw Output: 'NRPE: Command 'get_hostname' not defined'
[DEBUG]  -> Exit Code: 2
```

**Zabbix communication issues:**
```
Response from "192.168.1.100:10051": "processed: 0; failed: 1; total: 1; seconds spent: 0.000062"
```

For comprehensive troubleshooting guidance, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
