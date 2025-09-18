#!/bin/bash
#
# setup_cron_jobs.sh: Sets up cron jobs for Zabbix NRPE monitoring with trapper mode
#
# This script configures cron jobs to:
# 1. Run host discovery every hour
# 2. Run metrics collection every minute
# 3. Run metrics discovery every hour (after host discovery)
#
# Usage: ./setup_cron_jobs.sh [--zabbix-server SERVER] [--zabbix-port PORT] [--hostname HOST] [--ip-ranges "RANGES"] [--user USER]
#

# --- Default Configuration ---
ZABBIX_SERVER=""
ZABBIX_PORT="10051"
ZABBIX_HOSTNAME=""
CRON_USER="zabbix"
IP_RANGES=""
SCRIPT_DIR="/usr/lib/zabbix/externalscripts"
CACHE_FILE="/tmp/xenapp_hosts_cache.json"

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case $1 in
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
    --ip-ranges)
      IP_RANGES="$2"
      shift 2
      ;;
    --script-dir)
      SCRIPT_DIR="$2"
      shift 2
      ;;
    --cache-file)
      CACHE_FILE="$2"
      shift 2
      ;;
    --user)
      CRON_USER="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --zabbix-server SERVER    Zabbix server IP (default: 127.0.0.1)"
      echo "  --zabbix-port PORT        Zabbix server port (default: 10051)"
      echo "  --hostname HOST           Zabbix discovery host name (default: Discover XenServer)"
      echo "  --ip-ranges \"RANGES\"      Comma-separated IP ranges to scan (required)"
      echo "  --script-dir DIR          Directory containing the scripts (default: current dir)"
      echo "  --cache-file FILE         Cache file path (default: /tmp/xenapp_hosts_cache.json)"
      echo "  --user USER               User to run cron jobs as (default: zabbix)"
      echo "  -h, --help                Show this help message"
      echo ""
      echo "Example:"
      echo "  $0 --zabbix-server 192.168.1.1 --hostname MyDiscoveryHost --ip-ranges \"192.168.1.0/24,192.168.1.0/24\""
      exit 0
      ;;
    *)
      echo "Error: Unknown option $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# --- Validation ---
if [[ -z "$IP_RANGES" ]]; then
  echo "Error: IP ranges must be specified with --ip-ranges" >&2
  echo "Example: --ip-ranges \"192.168.1.0/24,192.168.1.0/24\"" >&2
  exit 1
fi

if [[ ! -d "$SCRIPT_DIR" ]]; then
  echo "Error: Script directory not found: $SCRIPT_DIR" >&2
  exit 1
fi

# Check if required scripts exist
REQUIRED_SCRIPTS=(
  "discover_xenapp_hosts.sh"
  "discover_xenapp_metrics.sh"
  "query_xen_server.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
  if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
    echo "Error: Required script not found: $SCRIPT_DIR/$script" >&2
    exit 1
  fi
  
  # Make scripts executable
  chmod +x "$SCRIPT_DIR/$script"
done

# Check for required tools
REQUIRED_TOOLS=("nmap" "check_nrpe" "zabbix_sender")
OPTIONAL_TOOLS=("jq")

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: Required tool not found: $tool" >&2
    echo "Please install the required tools before setting up cron jobs." >&2
    exit 1
  fi
done

for tool in "${OPTIONAL_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Warning: Optional tool not found: $tool" >&2
    echo "The scripts will work without it, but installing it is recommended for better performance." >&2
  fi
done

echo "Setting up cron jobs for Zabbix NRPE monitoring..."
echo "Configuration:"
echo "  Zabbix Server: $ZABBIX_SERVER:$ZABBIX_PORT"
echo "  Discovery Host: $ZABBIX_HOSTNAME"
echo "  Cron User: $CRON_USER"
echo "  IP Ranges: $IP_RANGES"
echo "  Script Directory: $SCRIPT_DIR"
echo "  Cache File: $CACHE_FILE"
echo ""

# --- Create Cron Jobs ---
TEMP_CRON=$(mktemp)

# Check if user exists
if ! id "$CRON_USER" &>/dev/null; then
  echo "Error: User '$CRON_USER' does not exist on this system" >&2
  echo "Please create the user or specify a different user with --user" >&2
  exit 1
fi

# Keep existing cron jobs (except our monitoring jobs)
if [[ "$CRON_USER" == "$(whoami)" ]]; then
  crontab -l 2>/dev/null | grep -v "# Zabbix NRPE Monitoring" > "$TEMP_CRON" || true
else
  crontab -u "$CRON_USER" -l 2>/dev/null | grep -v "# Zabbix NRPE Monitoring" > "$TEMP_CRON" || true
fi

# Add our cron jobs
cat >> "$TEMP_CRON" << EOF

# Zabbix NRPE Monitoring - Host Discovery (runs every hour at minute 5)
0 6 * * * $SCRIPT_DIR/discover_xenapp_hosts.sh "$IP_RANGES" --trapper --hostname "$ZABBIX_HOSTNAME" --zabbix-server $ZABBIX_SERVER --zabbix-port $ZABBIX_PORT --cache-file $CACHE_FILE >> /var/log/zabbix/xenapp_discovery.log 2>&1

# Zabbix NRPE Monitoring - Metrics Discovery (runs daily at 06:05, 5 minutes after host discovery)
5 6 * * * $SCRIPT_DIR/discover_xenapp_metrics.sh --trapper --zabbix-server $ZABBIX_SERVER --zabbix-port $ZABBIX_PORT --cache-file $CACHE_FILE >> /var/log/zabbix/xenapp_metrics_discovery.log 2>&1

# Zabbix NRPE Monitoring - Metrics Collection (runs every minute)
* * * * * $SCRIPT_DIR/query_xen_server.sh --trapper --zabbix-server $ZABBIX_SERVER --zabbix-port $ZABBIX_PORT --cache-file $CACHE_FILE >> /var/log/zabbix/xenapp_metrics.log 2>&1

EOF

# Install the new crontab
if [[ "$CRON_USER" == "$(whoami)" ]]; then
  if crontab "$TEMP_CRON"; then
    echo "✓ Cron jobs installed successfully for user $(whoami)!"
  else
    echo "✗ Failed to install cron jobs" >&2
    rm -f "$TEMP_CRON"
    exit 1
  fi
else
  if crontab -u "$CRON_USER" "$TEMP_CRON"; then
    echo "✓ Cron jobs installed successfully for user $CRON_USER!"
  else
    echo "✗ Failed to install cron jobs for user $CRON_USER" >&2
    echo "Note: You may need to run this script as root or with sudo to install cron jobs for other users" >&2
    rm -f "$TEMP_CRON"
    exit 1
  fi
fi

rm -f "$TEMP_CRON"

# --- Create Log Rotation Configuration ---
LOG_ROTATE_FILE="/etc/logrotate.d/xenapp-monitoring"
cat > "$LOG_ROTATE_FILE" << 'EOF'
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
        # Ensure zabbix user owns the new log files
        chown zabbix:zabbix /var/log/zabbix/xenapp_*.log 2>/dev/null || true
    endscript
}
EOF

echo "✓ Log rotation configured"

# --- Create Initial Cache File ---
if [[ ! -f "$CACHE_FILE" ]]; then
  echo '{"hosts":{},"last_updated":0}' > "$CACHE_FILE"
  chmod 644 "$CACHE_FILE"
  chown zabbix:zabbix "$CACHE_FILE"
  echo "✓ Initial cache file created: $CACHE_FILE"
fi

# --- Ensure Log Directory Exists and Has Correct Permissions ---
if [[ ! -d "/var/log/zabbix" ]]; then
  mkdir -p /var/log/zabbix
  chown zabbix:zabbix /var/log/zabbix
  chmod 755 /var/log/zabbix
  echo "✓ Created /var/log/zabbix directory with proper permissions"
else
  chown zabbix:zabbix /var/log/zabbix
  chmod 755 /var/log/zabbix
  echo "✓ Verified /var/log/zabbix directory permissions"
fi

# --- Run Initial Discovery ---
echo ""
echo "Running initial host discovery..."
if "$SCRIPT_DIR/Scripts/discover_xenapp_hosts.sh" "$IP_RANGES" --trapper --hostname "$ZABBIX_HOSTNAME" --zabbix-server "$ZABBIX_SERVER" --zabbix-port "$ZABBIX_PORT" --cache-file "$CACHE_FILE"; then
  echo "✓ Initial host discovery completed"
  
  echo "Running initial metrics discovery..."
  if "$SCRIPT_DIR/Scripts/discover_xenapp_metrics.sh" --trapper --zabbix-server "$ZABBIX_SERVER" --zabbix-port "$ZABBIX_PORT" --cache-file "$CACHE_FILE"; then
    echo "✓ Initial metrics discovery completed"
  else
    echo "⚠ Initial metrics discovery failed (this is normal if no hosts were found)"
  fi
else
  echo "⚠ Initial host discovery failed"
fi

echo ""
echo "Setup completed successfully!"
echo ""
echo "Cron Schedule:"
echo "  Host Discovery:     Daily at 06:00 (6 AM)"
echo "  Metrics Discovery:  Daily at 06:05 (5 minutes after host discovery)"
echo "  Metrics Collection: Every minute"
echo ""
echo "Log Files:"
echo "  Host Discovery:     /var/log/zabbix/xenapp_discovery.log"
echo "  Metrics Discovery:  /var/log/zabbix/xenapp_metrics_discovery.log"
echo "  Metrics Collection: /var/log/zabbix/xenapp_metrics.log"
echo ""
echo "Cache File: $CACHE_FILE"
echo ""
echo "To view current status:"
echo "  tail -f /var/log/zabbix/xenapp_*.log"
echo ""
echo "To view discovered hosts:"
echo "  jq '.hosts' $CACHE_FILE"
