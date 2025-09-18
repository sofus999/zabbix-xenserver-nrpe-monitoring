#!/bin/bash
#
# query_xen_server.sh: Fetches all metrics from XenServers in bulk
# and outputs them as a single JSON object to stdout or sends via Zabbix trapper.
# Includes corrected parsing for all metric types and caching support.
#
# Usage: 
#   External Check mode: ./query_xen_server.sh <XenServer_IP> [-d|--debug]
#   Trapper mode: ./query_xen_server.sh --trapper [--cache-file FILE] [--zabbix-server SERVER] [--zabbix-port PORT] [-d|--debug]
#

# set -e  # Disabled: We handle errors explicitly in trapper mode

# Set PATH to ensure commands are found when run from cron
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/nagios/plugins"

# --- Configuration ---
CACHE_FILE="/tmp/xenapp_hosts_cache.json"
CACHE_LOCK="/tmp/xenapp_hosts_cache.lock"
TRAPPER_MODE=0
ZABBIX_SERVER=""
ZABBIX_PORT="10051"
DEBUG=0
XENSERVER_HOST=""
IP_REGEX="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

# --- Argument Parsing & Validation ---
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
    -d|--debug)
      DEBUG=1
      shift
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$XENSERVER_HOST" ]]; then
        XENSERVER_HOST=$1
      else
        echo "Error: Multiple hosts provided. This script processes one host at a time." >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# In trapper mode, we get hosts from cache. In external check mode, we need a host parameter.
if [[ $TRAPPER_MODE -eq 1 ]]; then
  # Trapper mode: should not have a host parameter
  if [[ -n "$XENSERVER_HOST" ]]; then
    echo "Error: In trapper mode, hosts are read from cache. Do not provide IP address parameter." >&2
    echo "Usage: $0 --trapper [--cache-file FILE] [--zabbix-server SERVER] [--zabbix-port PORT] [-d|--debug]" >&2
    exit 1
  fi
else
  # External check mode: requires a host parameter
  if [[ -z "$XENSERVER_HOST" ]]; then
    echo "Error: You must provide the XenServer IP address." >&2
    echo "Usage: $0 <XenServer_IP> [-d|--debug]" >&2
    echo "   or: $0 --trapper [--cache-file FILE] [--zabbix-server SERVER] [--zabbix-port PORT] [-d|--debug]" >&2
    exit 1
  fi

  if ! [[ $XENSERVER_HOST =~ $IP_REGEX ]]; then
    echo "Error: Invalid IP address format provided: $XENSERVER_HOST" >&2
    exit 1
  fi
fi

debug_msg() {
  if [ "$DEBUG" -eq 1 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >&2
  fi
}

log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Wait for cache lock to be available (read-only, short wait)
wait_for_cache_unlock() {
  local timeout=5  # Short timeout for read operations
  local count=0
  while [[ -f "$CACHE_LOCK" && $count -lt $timeout ]]; do
    sleep 0.1
    ((count++))
  done
  # Don't exit if lock exists - just log and continue (read operation should be safe)
  if [[ -f "$CACHE_LOCK" ]]; then
    debug_msg "Cache lock detected, but continuing with read operation"
  fi
}

# Load hosts from cache
load_hosts_from_cache() {
  # Wait briefly for any ongoing cache updates to complete
  wait_for_cache_unlock
  
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

# Query metrics for a single host
query_host_metrics() {
  local host_ip="$1"
  local host_name="$2"
  
  # --- JSON Generation ---
  printf "{\n"

  FIRST_ITEM=1
  for item in "${METRICS[@]}"; do
    NRPE_CMD=$(echo "$item" | cut -d':' -f1)
    METRIC_KEY=$(echo "$item" | cut -d':' -f2)

    debug_msg "----------------------------------"
    debug_msg "Processing metric: $METRIC_KEY for host $host_ip"

    # Run with SSL, but allow it to fail without exiting the whole script
    raw_output=$(check_nrpe -H "$host_ip" -c "$NRPE_CMD" 2>/dev/null || true)
    exit_code=$?
    debug_msg " -> NRPE Command:  check_nrpe -H $host_ip -c $NRPE_CMD"
    debug_msg " -> Raw Output:    '$raw_output'"
    debug_msg " -> Exit Code:     $exit_code"

    value=""
    perfdata=$(echo "$raw_output" | awk -F'|' '{print $2}')

    case "$NRPE_CMD" in
      check_host_load|check_load)
        # --- START: Load Average Parsing Logic ---
        # Parse different load average values based on metric key
        # Try to extract from main output first (handles multiple values)
        load_values=$(echo "$raw_output" | grep -o 'load average[^:]*: [0-9.]*\(, [0-9.]*\)*\(, [0-9.]*\)*' | sed 's/.*: //')
        
        if [[ "$METRIC_KEY" == *".1min" ]]; then
          # Extract 1-minute load average from performance data (load1=X)
          value=$(echo "$perfdata" | grep -o 'load1=[0-9.]*' | cut -d'=' -f2)
          # Fallback to first value from text output if perfdata parsing fails
          if [[ -z "$value" && -n "$load_values" ]]; then
            value=$(echo "$load_values" | awk -F'[, ]+' '{print $1}')
          fi
        elif [[ "$METRIC_KEY" == *".5min" ]]; then
          # Extract 5-minute load average from performance data (load5=X)
          value=$(echo "$perfdata" | grep -o 'load5=[0-9.]*' | cut -d'=' -f2)
          # Fallback to second value from text output if perfdata parsing fails
          if [[ -z "$value" && -n "$load_values" ]]; then
            value=$(echo "$load_values" | awk -F'[, ]+' '{print $2}')
            # If no second value, use first value as fallback
            if [[ -z "$value" ]]; then
              value=$(echo "$load_values" | awk -F'[, ]+' '{print $1}')
            fi
          fi
        elif [[ "$METRIC_KEY" == *".15min" ]]; then
          # Extract 15-minute load average from performance data (load15=X)
          value=$(echo "$perfdata" | grep -o 'load15=[0-9.]*' | cut -d'=' -f2)
          # Fallback to third value from text output if perfdata parsing fails
          if [[ -z "$value" && -n "$load_values" ]]; then
            value=$(echo "$load_values" | awk -F'[, ]+' '{print $3}')
            # If no third value, use first value as fallback
            if [[ -z "$value" ]]; then
              value=$(echo "$load_values" | awk -F'[, ]+' '{print $1}')
            fi
          fi
        else
          # Default: 1-minute load average from performance data
          value=$(echo "$perfdata" | grep -o 'load1=[0-9.]*' | cut -d'=' -f2)
          # Fallback to generic parsing if no specific load1 found
          if [[ -z "$value" ]]; then
            value=$(echo "$perfdata" | awk -F'[=;]' '{print $2}')
          fi
        fi
        # --- END: Load Average Parsing Logic ---
        ;;
      check_host_cpu|check_cpu|check_memory)
        value=$(echo "$perfdata" | awk -F'[=;]' '{print $2}' | sed 's/[^0-9.]*//g')
        ;;
      check_vgpu|check_vgpu_memory)
        # --- START: vGPU Error Handling Logic ---
        # Check for UNKNOWN status or error conditions - send raw output for errors
        if [[ "$raw_output" =~ ^UNKNOWN ]] || [[ "$raw_output" =~ "No such file or directory" ]] || [[ "$raw_output" =~ "Check failed" ]]; then
          value="$raw_output"  # Send the raw error message
        else
          value=$(echo "$perfdata" | awk -F'[=;]' '{print $2}' | sed 's/[^0-9.]*//g')
          if [[ -z "$value" ]]; then
            value="0"  # Default to 0 if parsing fails but no error detected
          fi
        fi
        # --- END: vGPU Error Handling Logic ---
        ;;
      check_disk_root|check_disk_log)
        # --- START: Corrected Disk Parsing Logic ---
        # Extracts "86.52" from a string like "(86.52% inode=92%)"
        percent_free=$(echo "$raw_output" | grep -o '([0-9.]*% inode=' | sed 's/[()%]//g' | sed 's/ inode=//g')
        # Calculate % used
        if [[ "$percent_free" =~ ^[0-9]+\.?[0-9]*$ ]]; then
          # Use bc for decimal calculation if available, otherwise use integer math
          if command -v bc >/dev/null 2>&1; then
            value=$(echo "100 - $percent_free" | bc)
          else
            # Fallback to integer math (will truncate decimals)
            percent_free_int=${percent_free%.*}  # Remove decimal part
            value=$((100 - percent_free_int))
          fi
        else
          value="$raw_output"  # Send raw output if parsing fails
        fi
        # --- END: Corrected Disk Parsing Logic ---
        ;;
      check_swap)
        # --- START: Swap Usage Percentage Logic ---
        # Extract "100% free" from "SWAP OK - 100% free (1023 MB out of 1023 MB)"
        percent_free=$(echo "$raw_output" | grep -o '[0-9]*% free' | grep -o '[0-9]*')
        # Calculate % used (opposite of free)
        if [[ "$percent_free" =~ ^[0-9]+$ ]]; then
          value=$((100 - percent_free))
        else
          value="0"  # Default to 0% used if parsing fails
        fi
        # --- END: Swap Usage Percentage Logic ---
        ;;
      check_xapi)
        # --- START: XAPI Status Boolean Logic ---
        # Return 1 for OK, 0 for any other status
        if [[ "$raw_output" =~ ^OK ]]; then
          value="1"  # Service is up
        else
          value="0"  # Service is down
        fi
        # --- END: XAPI Status Boolean Logic ---
        ;;
      *)
        value=$(echo "$perfdata" | awk -F'[=;]' '{print $2}' | sed 's/[^0-9.]*//g')
        if [[ -z "$value" ]]; then
          # If we can't parse a numeric value, send the raw output for troubleshooting
          if [[ -n "$raw_output" ]]; then
            value="$raw_output"
          else
            value=$exit_code
          fi
        fi
        ;;
    esac

    debug_msg " -> Parsed Value:  '$value'"

    if [ $FIRST_ITEM -eq 0 ]; then
      printf ",\n"
    fi

    printf '  "%s": "%s"' "$METRIC_KEY" "$value"
    FIRST_ITEM=0
  done

  printf "\n}\n"
}

# Send metrics to Zabbix via trapper
send_metrics_to_zabbix() {
  local host_ip="$1"
  local host_name="$2"
  local metrics_json="$3"
  
  if ! command -v zabbix_sender >/dev/null 2>&1; then
    log_message "ERROR: zabbix_sender not found. Please install zabbix-sender package."
    return 1
  fi
  
  # Use parameter method like the working Storage Protect script
  # Send the complete JSON as the master item
  CLEAN_JSON=$(echo "$metrics_json" | tr -d '\n\r')
  
  debug_msg "Sending master item to Zabbix server $ZABBIX_SERVER:$ZABBIX_PORT"
  debug_msg "Host: $host_name, Key: nrpe.master.data"
  
  # Send master item using config file approach like Storage Protect script
  local send_success=0
  if [[ -f "/etc/zabbix/zabbix_agent2.conf" ]]; then
    if zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -s "$host_name" -k "nrpe.master.data" -o "$CLEAN_JSON" >/dev/null 2>&1; then
      send_success=1
    fi
  else
    if zabbix_sender -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$host_name" -k "nrpe.master.data" -o "$CLEAN_JSON" >/dev/null 2>&1; then
      send_success=1
    fi
  fi
  
  if [[ $send_success -eq 1 ]]; then
    debug_msg "Master item sent successfully for host $host_name"
    
    # Send individual metrics (these will be processed by dependent items)
    if command -v jq >/dev/null 2>&1; then
      echo "$metrics_json" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
          if [[ -f "/etc/zabbix/zabbix_agent2.conf" ]]; then
            zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -s "$host_name" -k "nrpe.[$key]" -o "$value" >/dev/null 2>&1
          else
            zabbix_sender -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$host_name" -k "nrpe.[$key]" -o "$value" >/dev/null 2>&1
          fi
        fi
      done
    else
      # Fallback without jq - parse JSON manually
      echo "$metrics_json" | grep -o '"[^"]*":"[^"]*"' | while read -r line; do
        key=$(echo "$line" | cut -d':' -f1 | sed 's/"//g')
        value=$(echo "$line" | cut -d':' -f2 | sed 's/"//g')
        if [[ -n "$key" && -n "$value" ]]; then
          if [[ -f "/etc/zabbix/zabbix_agent2.conf" ]]; then
            zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -s "$host_name" -k "nrpe.[$key]" -o "$value" >/dev/null 2>&1
          else
            zabbix_sender -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$host_name" -k "nrpe.[$key]" -o "$value" >/dev/null 2>&1
          fi
        fi
      done
    fi
  else
    log_message "ERROR: Failed to send master item for host $host_name"
  fi
}

# --- Metric Definitions ---
METRICS=(
  "check_host_load:host.load.1min"
  "check_host_load:host.load.5min"
  "check_host_load:host.load.15min"
  "check_host_cpu:host.cpu"
  "check_host_memory:host.memory"
  "check_vgpu:host.vgpu"
  "check_vgpu_memory:host.vgpu_memory"
  "check_load:dom0.load.1min"
  "check_load:dom0.load.5min"
  "check_load:dom0.load.15min"
  "check_cpu:dom0.cpu"
  "check_memory:dom0.memory"
  "check_swap:dom0.swap"
  "check_disk_root:dom0.disk.root"
  "check_disk_log:dom0.disk.log"
  "check_xapi:xapi.status"
  "check_multipath:multipath.status"
)

# --- Main Execution Logic ---
if [[ $TRAPPER_MODE -eq 1 ]]; then
  # Trapper mode: process all hosts from cache
  log_message "Starting metrics collection in trapper mode"
  
  if [[ ! -f "$CACHE_FILE" ]]; then
    log_message "ERROR: Cache file not found: $CACHE_FILE. Run discovery first."
    exit 1
  fi
  
  PROCESSED_COUNT=0
  ERROR_COUNT=0
  
  # Load all hosts into an array to avoid stdin redirection issues
  debug_msg "Loading hosts from cache..."
  mapfile -t HOST_LINES < <(load_hosts_from_cache)
  
  if [[ $DEBUG -eq 1 ]]; then
    debug_msg "Total hosts loaded: ${#HOST_LINES[@]}"
    debug_msg "First 5 hosts:"
    for ((i=0; i<5 && i<${#HOST_LINES[@]}; i++)); do
      debug_msg "  ${HOST_LINES[$i]}"
    done
  fi
  
  # Process each host
  for i in "${!HOST_LINES[@]}"; do
    HOST_LINE="${HOST_LINES[$i]}"
    if [[ -n "$HOST_LINE" ]]; then
      IFS=':' read -r HOST_IP HOST_NAME <<< "$HOST_LINE"
      
      if [[ -n "$HOST_IP" ]]; then
        debug_msg "Processing host $((i+1))/${#HOST_LINES[@]}: $HOST_IP ($HOST_NAME)"
        
        # Query metrics for this host
        METRICS_JSON=$(query_host_metrics "$HOST_IP" "$HOST_NAME")
        QUERY_EXIT_CODE=$?
        debug_msg "query_host_metrics returned exit code: $QUERY_EXIT_CODE"
        
        if [[ $QUERY_EXIT_CODE -eq 0 && -n "$METRICS_JSON" ]]; then
          # Send to Zabbix
          send_metrics_to_zabbix "$HOST_IP" "$HOST_NAME" "$METRICS_JSON"
          SEND_EXIT_CODE=$?
          debug_msg "send_metrics_to_zabbix returned exit code: $SEND_EXIT_CODE"
          ((PROCESSED_COUNT++))
          debug_msg "Completed host $((i+1))/${#HOST_LINES[@]}, moving to next..."
        else
          log_message "ERROR: Failed to collect metrics for host $HOST_IP ($HOST_NAME)"
          ((ERROR_COUNT++))
          
          # Send empty/error data to maintain item activity (prevents nodata trigger issues)
          ERROR_JSON='{"host.load":"0","host.cpu":"0","host.memory":"0","host.vgpu":"0","host.vgpu_memory":"0","dom0.load":"0","dom0.cpu":"0","dom0.memory":"0","dom0.swap":"0","dom0.disk.root":"0","dom0.disk.log":"0","xapi.status":"1","multipath.status":"1"}'
          send_metrics_to_zabbix "$HOST_IP" "$HOST_NAME" "$ERROR_JSON"
          debug_msg "Sent error data for host $((i+1))/${#HOST_LINES[@]}, moving to next..."
        fi
      fi
    fi
  done
  
  log_message "Metrics collection completed. Processed: $PROCESSED_COUNT, Errors: $ERROR_COUNT"
  
else
  # External check mode: process single host
  if [[ -z "$XENSERVER_HOST" ]]; then
    echo "Error: Host IP required in external check mode" >&2
    exit 1
  fi
  
  # Use the original hostname logic for external check mode
  HOSTNAME=$(timeout 10 check_nrpe -H "$XENSERVER_HOST" -c get_hostname 2>/dev/null || echo "$XENSERVER_HOST")
  
  # Query and output metrics
  query_host_metrics "$XENSERVER_HOST" "$HOSTNAME"
fi
