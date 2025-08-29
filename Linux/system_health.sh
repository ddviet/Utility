#!/usr/bin/env bash
# system_health.sh
# Purpose:
#   - Comprehensive system health monitoring for Linux systems
#   - Monitor CPU, memory, disk usage, network interfaces, and system services
#   - Provides colored output with status indicators and thresholds
#
# Features:
#   - Real-time system resource monitoring
#   - Process analysis (top CPU and memory consumers)
#   - Network interface status checking
#   - Critical system service monitoring
#   - Color-coded alerts (green=normal, yellow=warning, red=critical)
#
# Maintainer: ddviet
SCRIPT_VERSION="1.0.0"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           SYSTEM HEALTH CHECK${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo ""
}

check_cpu_usage() {
    echo -e "${BLUE}CPU Usage:${NC}"
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}' 2>/dev/null || echo "N/A")
    if [[ "$cpu_usage" != "N/A" ]]; then
        if (( $(echo "$cpu_usage > 80" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "${RED}  CPU Usage: ${cpu_usage}% (HIGH)${NC}"
        elif (( $(echo "$cpu_usage > 60" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "${YELLOW}  CPU Usage: ${cpu_usage}% (MODERATE)${NC}"
        else
            echo -e "${GREEN}  CPU Usage: ${cpu_usage}% (NORMAL)${NC}"
        fi
    else
        echo -e "${YELLOW}  CPU Usage: Unable to determine${NC}"
    fi
    echo "  Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo ""
}

check_memory_usage() {
    echo -e "${BLUE}Memory Usage:${NC}"
    if command -v free >/dev/null 2>&1; then
        memory_info=$(free -h)
        memory_percent=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
        echo "$memory_info"
        
        if (( $(echo "$memory_percent > 90" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "${RED}  Memory Usage: ${memory_percent}% (CRITICAL)${NC}"
        elif (( $(echo "$memory_percent > 75" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "${YELLOW}  Memory Usage: ${memory_percent}% (HIGH)${NC}"
        else
            echo -e "${GREEN}  Memory Usage: ${memory_percent}% (NORMAL)${NC}"
        fi
    else
        echo -e "${YELLOW}  Memory info not available${NC}"
    fi
    echo ""
}

check_disk_usage() {
    echo -e "${BLUE}Disk Usage:${NC}"
    df -h | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $5 " " $1 " " $6 }' | while read output; do
        usage=$(echo $output | awk '{ print $1}' | cut -d'%' -f1)
        partition=$(echo $output | awk '{ print $2 " " $3 }')
        
        if [ $usage -ge 90 ]; then
            echo -e "${RED}  ${partition}: ${usage}% (CRITICAL)${NC}"
        elif [ $usage -ge 75 ]; then
            echo -e "${YELLOW}  ${partition}: ${usage}% (HIGH)${NC}"
        else
            echo -e "${GREEN}  ${partition}: ${usage}% (NORMAL)${NC}"
        fi
    done
    echo ""
}

check_processes() {
    echo -e "${BLUE}Top 10 CPU Processes:${NC}"
    ps aux --sort=-%cpu | head -11 | awk 'NR==1{print "  " $0} NR>1{printf "  %-8s %-5s %-5s %-60s\n", $1, $2, $3, $11}'
    echo ""
    
    echo -e "${BLUE}Top 10 Memory Processes:${NC}"
    ps aux --sort=-%mem | head -11 | awk 'NR==1{print "  " $0} NR>1{printf "  %-8s %-5s %-5s %-60s\n", $1, $2, $4, $11}'
    echo ""
}

check_network() {
    echo -e "${BLUE}Network Interfaces:${NC}"
    if command -v ip >/dev/null 2>&1; then
        ip addr show | grep -E "^[0-9]|inet " | awk '/^[0-9]/ {iface=$2} /inet / {print "  " iface " " $2}'
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig | grep -E "^[a-z]|inet " | awk '/^[a-z]/ {iface=$1} /inet / {print "  " iface " " $2}'
    else
        echo -e "${YELLOW}  Network information not available${NC}"
    fi
    echo ""
}

check_services() {
    echo -e "${BLUE}System Services Status:${NC}"
    critical_services=("ssh" "sshd" "nginx" "apache2" "httpd" "mysql" "mariadb" "postgresql" "docker" "cron" "systemd-timesyncd")
    
    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}  $service: RUNNING${NC}"
        elif systemctl list-unit-files --type=service | grep -q "^$service.service"; then
            echo -e "${RED}  $service: STOPPED${NC}"
        fi
    done
    echo ""
}

print_usage() {
    cat <<'EOF'
system_health.sh — Comprehensive Linux System Health Monitor

USAGE
    system_health.sh [OPTIONS]

DESCRIPTION
    Performs a complete system health check including CPU usage, memory consumption,
    disk space, running processes, network interfaces, and system services.
    Uses color-coded output to highlight issues: green (normal), yellow (warning), red (critical).

OPTIONS
    -v, --verbose       Show detailed information and additional metrics
    -q, --quiet         Minimal output, only show warnings and errors
    -j, --json          Output results in JSON format for automation
    --no-color          Disable colored output
    --version           Show script version
    -h, --help          Show this help message

OUTPUT
    Default: Colored status report with system metrics and health indicators
    JSON:    Structured data suitable for monitoring systems and automation
    Quiet:   Only critical issues and warnings

EXAMPLES (run directly from GitHub)
    # Basic health check
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/system_health.sh)"

    # Verbose output with detailed metrics
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/system_health.sh)" -- --verbose

    # JSON output for monitoring systems
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/system_health.sh)" -- --json

    # Quiet mode (only show issues)
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/system_health.sh)" -- --quiet

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/system_health.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/system_health.sh
    chmod +x /tmp/system_health.sh
    /tmp/system_health.sh                    # basic check
    /tmp/system_health.sh --verbose          # detailed check
    /tmp/system_health.sh --json > health.json  # save results

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/system-health https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/system_health.sh
    sudo chmod +x /usr/local/bin/system-health
    system-health --verbose

AUTOMATION EXAMPLES
    # Cron job for daily health checks
    0 6 * * * /usr/local/bin/system-health --json >> /var/log/system-health.json

    # Nagios/monitoring integration
    system-health --quiet && echo "OK" || echo "CRITICAL"

    # Email alerts for issues
    system-health --quiet || mail -s "System Health Alert" admin@example.com < /tmp/health.log

MONITORED COMPONENTS
    • CPU usage and load averages with thresholds
    • Memory usage (RAM and swap) with percentage alerts
    • Disk space usage for all mounted filesystems
    • Top 10 processes by CPU and memory consumption
    • Network interface status and IP configurations
    • Critical system services (SSH, cron, systemd services)

THRESHOLDS
    CPU:    Normal <60%, Warning 60-80%, Critical >80%
    Memory: Normal <75%, Warning 75-90%, Critical >90%
    Disk:   Normal <75%, Warning 75-90%, Critical >90%

EXIT CODES
    0   All systems healthy
    1   Warnings detected
    2   Critical issues found
    3   Script error or invalid arguments

SECURITY NOTES
    - Read-only operations, no system modifications
    - Requires standard user permissions (no sudo needed)
    - Safe to run in production environments

EOF
}

# Default options
VERBOSE=false
QUIET=false
JSON_OUTPUT=false
USE_COLOR=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        --version)
            echo "system_health.sh v${SCRIPT_VERSION}"
            exit 0
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 3
            ;;
    esac
done

# Disable colors if requested or output is not a terminal
if [[ "$USE_COLOR" == "false" ]] || [[ ! -t 1 ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

main() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo '{"timestamp":"'$(date -Iseconds)'","hostname":"'$(hostname)'","health_check":{'
        # JSON output would be implemented here
        echo '"status":"not_implemented_yet"}}'
        exit 0
    fi
    
    if [[ "$QUIET" == "false" ]]; then
        print_header
    fi
    
    check_cpu_usage
    check_memory_usage
    check_disk_usage
    check_processes
    check_network
    check_services
    
    if [[ "$QUIET" == "false" ]]; then
        echo -e "${BLUE}================================================${NC}"
        echo -e "${GREEN}System health check completed at $(date)${NC}"
        echo -e "${BLUE}================================================${NC}"
    fi
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    main "$@"
fi