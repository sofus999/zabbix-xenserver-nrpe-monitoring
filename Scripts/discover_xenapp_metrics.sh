#!/bin/bash
#
# discover_xen_metrics.sh: Generates Zabbix LLD JSON for XenServer metrics,
# including the correct unit for each metric. Supports both External Check and Zabbix Trapper modes.
#
# Usage:
#   External Check mode: ./discover_xen_metrics.sh [host_ip]
#   Trapper mode: ./discover_xen_metrics.sh --trapper [--cache-file FILE] [--zabbix-server SERVER] [--zabbix-port PORT]
#

# Set PATH to ensure commands are found when run from cron
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/nagios/plugins"

# --- Configuration ---
CACHE_FILE="/tmp/xenapp_hosts_cache.json"
TRAPPER_MODE=0
ZABBIX_SERVER=""
ZABBIX_PORT="10051"
DISCOVERY_KEY="xenapp.metrics.discovery"

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --trapper)
      TRAPPER_MODE=1
      shift
      ;;
    --cache-file)
      CACHE_FILE="$2"
      shift 2
      ;;
    --zabbix-server)
      ZABBIX_SERVER="$2"
      shift 2
      ;;
    --zabbix-port)
      ZABBIX_PORT="$2"
      shift 2
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      exit 1
      ;;
    *)
      # In external check mode, we might get a host IP parameter (but we don't use it)
      shift
      ;;
  esac
done

# --- Functions ---
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Load hosts from cache for trapper mode
load_hosts_from_cache() {
  if [[ ! -f "$CACHE_FILE" ]]; then
    log_message "ERROR: Cache file not found: $CACHE_FILE"
    exit 1
  fi
  
  if command -v jq >/dev/null 2>&1; then
    if ! jq empty "$CACHE_FILE" 2>/dev/null; then
      log_message "ERROR: Cache file is corrupted: $CACHE_FILE"
      exit 1
    fi
    jq -r '.hosts // {} | to_entries[] | "\(.key):\(.value.hostname)"' "$CACHE_FILE"
  else
    # Fallback without jq - parse JSON manually
    if ! grep -q '"hosts"' "$CACHE_FILE"; then
      log_message "ERROR: Cache file appears corrupted: $CACHE_FILE"
      exit 1
    fi
    grep -o '"[0-9.]*":{"hostname":"[^"]*"' "$CACHE_FILE" | sed 's/"//g' | sed 's/:{"hostname":/:/'
  fi
}

# --- Metric Definitions with Units ---
# Format: "NRPE_COMMAND:ZABBIX_KEY:UNIT"
METRICS=(
  "check_host_load:host.load.1min:"
  "check_host_load:host.load.5min:"
  "check_host_load:host.load.15min:"
  "check_host_cpu:host.cpu:%"
  "check_host_memory:host.memory:%"
  "check_vgpu:host.vgpu:%"
  "check_vgpu_memory:host.vgpu_memory:%"
  "check_load:dom0.load.1min:"
  "check_load:dom0.load.5min:"
  "check_load:dom0.load.15min:"
  "check_cpu:dom0.cpu:%"
  "check_memory:dom0.memory:%"
  "check_swap:dom0.swap:%"
  "check_disk_root:dom0.disk.root:%"
  "check_disk_log:dom0.disk.log:%"
  "check_xapi:xapi.status:"
  "check_multipath:multipath.status:"
)

# --- Generate Metrics Discovery JSON ---
generate_metrics_json() {
  local json_data='{"data":['
  local first_item=1
  
  for item in "${METRICS[@]}"; do
    local nrpe_cmd=$(echo "$item" | cut -d':' -f1)
    local metric_key=$(echo "$item" | cut -d':' -f2)
    local unit=$(echo "$item" | cut -d':' -f3)

    if [ $first_item -eq 0 ]; then
      json_data+=','
    fi

    json_data+='{"'
    json_data+='{#ZABBIX_KEY}":"'$metric_key'","'
    json_data+='{#UNIT}":"'$unit'"}'
    first_item=0
  done
  
  json_data+=']}'
  echo "$json_data"
}

# --- Main Execution Logic ---
METRICS_JSON=$(generate_metrics_json)

if [[ $TRAPPER_MODE -eq 1 ]]; then
  # Trapper mode: send discovery data for all cached hosts
  log_message "Starting metrics discovery in trapper mode"
  
  if [[ ! -f "$CACHE_FILE" ]]; then
    log_message "ERROR: Cache file not found: $CACHE_FILE. Run host discovery first."
    exit 1
  fi
  
  if ! command -v zabbix_sender >/dev/null 2>&1; then
    log_message "ERROR: zabbix_sender not found. Please install zabbix-sender package."
    exit 1
  fi
  
  # The metrics discovery data is static, so we can send it once to each host
  # But only after hosts have been created by the host discovery process
  CLEAN_JSON=$(echo "$METRICS_JSON" | tr -d '\n\r')
  SUCCESS_COUNT=0
  ERROR_COUNT=0
  
  # Send metrics discovery to each discovered host
  while IFS=':' read -r HOST_IP HOST_NAME; do
    if [[ -n "$HOST_IP" ]]; then
      # Try with config file first (like Storage Protect script), fallback to direct connection
      SUCCESS=0
      if [[ -f "/etc/zabbix/zabbix_agent2.conf" ]]; then
        if zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -s "$HOST_NAME" -k "$DISCOVERY_KEY" -o "$CLEAN_JSON" >/dev/null 2>&1; then
          SUCCESS=1
        fi
      else
        if zabbix_sender -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$HOST_NAME" -k "$DISCOVERY_KEY" -o "$CLEAN_JSON" >/dev/null 2>&1; then
          SUCCESS=1
        fi
      fi
      
      if [[ $SUCCESS -eq 1 ]]; then
        log_message "Metrics discovery sent successfully for host $HOST_NAME"
        ((SUCCESS_COUNT++))
      else
        log_message "WARN: Host $HOST_NAME may not exist in Zabbix yet - metrics discovery will be sent when host is created"
        ((ERROR_COUNT++))
      fi
    fi
  done < <(load_hosts_from_cache)
  
  log_message "Metrics discovery completed: $SUCCESS_COUNT succeeded, $ERROR_COUNT pending (hosts may not exist yet)"
  
else
  # External check mode: just output JSON
  echo "$METRICS_JSON"
fi
