#!/bin/bash
#
# discover_xenapp_hosts.sh: Scans IP addresses/ranges for responsive NRPE agents,
# fetches their hostname, and generates Zabbix LLD JSON for host discovery.
# Now supports Zabbix Trapper mode with persistent caching.
#
# Usage: 
#   External Check mode: ./discover_xenapp_hosts.sh "192.168.41.0/24,192.168.42.5"
#   Trapper mode: ./discover_xenapp_hosts.sh "192.168.41.0/24,192.168.42.5" --trapper [--hostname HOST] [--zabbix-server SERVER] [--zabbix-port PORT]
#

# Set PATH to ensure commands are found when run from cron
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/nagios/plugins"

# --- Configuration ---
CACHE_FILE="/tmp/xenapp_hosts_cache.json"
CACHE_LOCK="/tmp/xenapp_hosts_cache.lock"
TRAPPER_MODE=0
ZABBIX_SERVER=""
ZABBIX_PORT="10051"
ZABBIX_HOSTNAME=""
DISCOVERY_KEY="xenapp.host.discovery"
DEBUG=0

# --- Argument Parsing ---
SCAN_TARGETS=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --trapper)
      TRAPPER_MODE=1
      shift
      ;;
    --zabbix-server)
      ZABBIX_SERVER="$2"
      shift 2
      ;;
    --zabbix-port)
      ZABBIX_PORT="$2"
      shift 2
      ;;
    --hostname)
      ZABBIX_HOSTNAME="$2"
      shift 2
      ;;
    --cache-file)
      CACHE_FILE="$2"
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
      if [[ -z "$SCAN_TARGETS" ]]; then
        SCAN_TARGETS="$1"
      else
        echo "Error: Multiple scan targets provided. Use comma-separated values in a single argument." >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# --- Input Validation ---
if [[ -z "$SCAN_TARGETS" ]]; then
  echo "Error: No IP addresses or ranges provided." >&2
  echo "Usage: $0 \"192.168.1.0/24,192.168.2.5\" [--trapper] [--hostname HOST] [--zabbix-server SERVER] [--zabbix-port PORT] [--debug]" >&2
  exit 1
fi

# Convert the comma-separated input string into a space-separated list for nmap
SCAN_TARGETS=$(echo "$SCAN_TARGETS" | tr ',' ' ')

# --- Functions ---
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

debug_msg() {
  if [[ $DEBUG -eq 1 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >&2
  fi
}

# Acquire lock for cache operations
acquire_lock() {
  local timeout=30
  local count=0
  while ! (set -C; echo $$ > "$CACHE_LOCK") 2>/dev/null; do
    if [ $count -ge $timeout ]; then
      log_message "ERROR: Failed to acquire lock after $timeout seconds"
      exit 1
    fi
    sleep 1
    ((count++))
  done
  trap 'rm -f "$CACHE_LOCK"; exit' INT TERM EXIT
}

# Release lock
release_lock() {
  rm -f "$CACHE_LOCK"
  trap - INT TERM EXIT
}

# Load existing cache
load_cache() {
  if [[ -f "$CACHE_FILE" && -s "$CACHE_FILE" ]]; then
    # Try jq first, fallback to manual validation
    if command -v jq >/dev/null 2>&1; then
      if jq empty "$CACHE_FILE" 2>/dev/null; then
        cat "$CACHE_FILE"
      else
        log_message "WARN: Cache file is corrupted, starting fresh"
        echo '{"hosts":{},"last_updated":0}'
      fi
    else
      # Fallback: basic validation without jq
      if grep -q '"hosts"' "$CACHE_FILE" && grep -q '"last_updated"' "$CACHE_FILE"; then
        cat "$CACHE_FILE"
      else
        log_message "WARN: Cache file appears corrupted, starting fresh"
        echo '{"hosts":{},"last_updated":0}'
      fi
    fi
  else
    echo '{"hosts":{},"last_updated":0}'
  fi
}

# Save cache
save_cache() {
  local cache_data="$1"
  echo "$cache_data" > "$CACHE_FILE.tmp" && { rm -f "$CACHE_FILE"; mv "$CACHE_FILE.tmp" "$CACHE_FILE"; }
}

# --- Main Discovery Logic ---
if [[ $TRAPPER_MODE -eq 1 ]]; then
  acquire_lock
  log_message "Starting discovery in trapper mode"
fi

# Load existing cache
CACHE_DATA=$(load_cache)
CURRENT_TIME=$(date +%s)

# Use nmap to get a list of IPs with port 5666 open
log_message "Scanning targets: $SCAN_TARGETS"
IP_LIST=$(nmap -n -sT -p 5666 -T5 --max-retries 1 --host-timeout 5s -oG - --open $SCAN_TARGETS | awk '/Up$/{print $2}')
log_message "Found $(echo $IP_LIST | wc -w) responsive hosts"

# Process discovered hosts and update cache
UPDATED_HOSTS="{"
FIRST_HOST=1

# Add discovered hosts to cache (both new and existing ones get updated to active)
for IP in $IP_LIST; do
  log_message "Processing host: $IP"
  
  # For each found IP, try to get its hostname via NRPE, with a 10-second timeout
  HOSTNAME=$(timeout 10 check_nrpe -H "$IP" -c get_hostname 2>/dev/null)

  # If we didn't get a valid hostname, use the IP address as the name as a fallback
  if [[ -z "$HOSTNAME" || "$HOSTNAME" == *"not defined"* ]]; then
    HOSTNAME=$IP
  fi

  if [[ $FIRST_HOST -eq 0 ]]; then
    UPDATED_HOSTS+=","
  fi
  
  UPDATED_HOSTS+='"'$IP'":{"hostname":"'$HOSTNAME'","last_seen":'$CURRENT_TIME',"status":"active"}'
  FIRST_HOST=0
  log_message "Host $IP ($HOSTNAME) marked as active"
done

# Include existing hosts from cache (important: keep hosts even if not currently discovered)
if [[ $TRAPPER_MODE -eq 1 ]]; then
  if command -v jq >/dev/null 2>&1; then
    EXISTING_HOSTS=$(echo "$CACHE_DATA" | jq -r '.hosts // {} | to_entries[] | "\(.key):\(.value.hostname):\(.value.last_seen // 0):\(.value.status // "unknown")"')
  else
    # Fallback without jq - parse JSON manually (simplified)
    EXISTING_HOSTS=$(echo "$CACHE_DATA" | grep -o '"[0-9.]*":{"hostname":"[^"]*"' | sed 's/"//g' | sed 's/:.*hostname:/:/g' | sed 's/$/::unknown/')
  fi
  
  if [[ -n "$EXISTING_HOSTS" ]]; then
    while IFS=':' read -r CACHED_IP CACHED_HOSTNAME CACHED_LAST_SEEN CACHED_STATUS; do
      if [[ -n "$CACHED_IP" ]]; then
        # Check if this host was just discovered
        if ! echo "$IP_LIST" | grep -q "$CACHED_IP"; then
          # Host not currently responsive, but keep in cache as inactive
          if [[ $FIRST_HOST -eq 0 ]]; then
            UPDATED_HOSTS+=","
          fi
          UPDATED_HOSTS+='"'$CACHED_IP'":{"hostname":"'$CACHED_HOSTNAME'","last_seen":'${CACHED_LAST_SEEN:-0}',"status":"inactive"}'
          FIRST_HOST=0
          log_message "Keeping cached host in inactive state: $CACHED_IP ($CACHED_HOSTNAME)"
        else
          # Host is both cached AND currently discovered - it was already added as active above
          log_message "Host $CACHED_IP ($CACHED_HOSTNAME) is currently active and was updated"
        fi
      fi
    done <<< "$EXISTING_HOSTS"
  fi
fi

UPDATED_HOSTS+="}"

# Update cache with new data
if [[ $TRAPPER_MODE -eq 1 ]]; then
  if command -v jq >/dev/null 2>&1; then
    NEW_CACHE_DATA=$(echo '{}' | jq --argjson hosts "$UPDATED_HOSTS" --arg timestamp "$CURRENT_TIME" '.hosts = $hosts | .last_updated = ($timestamp | tonumber)')
    HOST_COUNT=$(echo "$UPDATED_HOSTS" | jq 'keys | length')
  else
    # Fallback without jq
    NEW_CACHE_DATA='{"hosts":'$UPDATED_HOSTS',"last_updated":'$CURRENT_TIME'}'
    HOST_COUNT=$(echo "$UPDATED_HOSTS" | grep -o '"[0-9.]*"' | wc -l)
  fi
  save_cache "$NEW_CACHE_DATA"
  log_message "Cache updated with $HOST_COUNT hosts"
fi

# Generate LLD JSON (include ALL hosts from cache for trapper mode, only active for external check mode)
if [[ $TRAPPER_MODE -eq 1 ]]; then
  # In trapper mode, include all cached hosts so nodata triggers can work
  ALL_HOSTS="$UPDATED_HOSTS"
else
  # In external check mode, only include currently active hosts
  ALL_HOSTS="{"
  FIRST_HOST=1
  for IP in $IP_LIST; do
    HOSTNAME=$(timeout 10 check_nrpe -H "$IP" -c get_hostname 2>/dev/null)
    if [[ -z "$HOSTNAME" || "$HOSTNAME" == *"not defined"* ]]; then
      HOSTNAME=$IP
    fi
    
    if [[ $FIRST_HOST -eq 0 ]]; then
      ALL_HOSTS+=","
    fi
    ALL_HOSTS+='"'$IP'":{"hostname":"'$HOSTNAME'"}'
    FIRST_HOST=0
  done
  ALL_HOSTS+="}"
fi

# --- JSON Generation ---
# Generate LLD JSON
if command -v jq >/dev/null 2>&1; then
  # Use jq for proper JSON formatting
  FINAL_JSON=$(echo "$ALL_HOSTS" | jq -r '
  {
    "data": [
      to_entries[] | {
        "{#HOST.IP}": .key,
        "{#HOST.NAME}": .value.hostname
      }
    ]
  }')
else
  # Fallback without jq - manual JSON generation
  FINAL_JSON='{"data":['
  FIRST_ITEM=1
  while IFS=':' read -r IP HOSTNAME; do
    if [[ -n "$IP" ]]; then
      if [[ $FIRST_ITEM -eq 0 ]]; then
        FINAL_JSON+=','
      fi
      FINAL_JSON+='{"{#HOST.IP}":"'$IP'","{#HOST.NAME}":"'$HOSTNAME'"}'
      FIRST_ITEM=0
    fi
  done < <(echo "$ALL_HOSTS" | grep -o '"[0-9.]*":{"hostname":"[^"]*"' | sed 's/"//g' | sed 's/:.*hostname:/:/g')
  FINAL_JSON+=']}'
fi

# In trapper mode, send to Zabbix server
if [[ $TRAPPER_MODE -eq 1 ]]; then
  TEMP_FILE=$(mktemp)
  echo "$FINAL_JSON" > "$TEMP_FILE"
  
  if command -v zabbix_sender >/dev/null 2>&1; then
    # Use parameter method like the working Storage Protect script
    JSON_DATA=$(cat "$TEMP_FILE" | tr -d '\n\r')
    
    # Debug: Show what we're sending
    if [[ $DEBUG -eq 1 ]]; then
      debug_msg "Sending to zabbix_sender:"
      debug_msg "Host: $ZABBIX_HOSTNAME"
      debug_msg "Key: $DISCOVERY_KEY"
      debug_msg "Data: $JSON_DATA"
    fi
    
    # Use the same method as your working Storage Protect script
    # Try with config file first (like Storage Protect script), fallback to direct connection
    if [[ -f "/etc/zabbix/zabbix_agent2.conf" ]]; then
      debug_msg "Using zabbix_agent2.conf config file"
      if [[ $DEBUG -eq 1 ]]; then
        zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -s "$ZABBIX_HOSTNAME" -k "$DISCOVERY_KEY" -o "$JSON_DATA" -vv
      else
        zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -s "$ZABBIX_HOSTNAME" -k "$DISCOVERY_KEY" -o "$JSON_DATA" >/dev/null 2>&1
      fi
    else
      debug_msg "Using direct connection parameters"
      if [[ $DEBUG -eq 1 ]]; then
        zabbix_sender -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$ZABBIX_HOSTNAME" -k "$DISCOVERY_KEY" -o "$JSON_DATA" -vv
      else
        zabbix_sender -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -s "$ZABBIX_HOSTNAME" -k "$DISCOVERY_KEY" -o "$JSON_DATA" >/dev/null 2>&1
      fi
    fi
    log_message "Discovery data sent to Zabbix server $ZABBIX_SERVER:$ZABBIX_PORT"
  else
    log_message "ERROR: zabbix_sender not found. Please install zabbix-sender package."
    exit 1
  fi
  
  rm -f "$TEMP_FILE"
  release_lock
  log_message "Discovery completed successfully"
else
  # External check mode - just output JSON
  cat <<< "$FINAL_JSON"
fi
