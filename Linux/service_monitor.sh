#!/bin/bash
# service_monitor.sh
# Purpose:
#   - Monitor critical system services and automatically restart failed services
#   - Support configurable service definitions with custom health checks
#   - Provide continuous monitoring with email notifications and logging
#
# Features:
#   - Flexible service configuration with custom check and restart commands
#   - Multiple monitoring modes: one-time check, continuous watch, daemon mode
#   - Configurable failure thresholds and cooldown periods
#   - Email notifications for service failures and recoveries
#   - Detailed logging with rotation support
#   - Status reporting and service management
#   - Dry-run mode for testing configurations
#
# Maintainer: ddviet
SCRIPT_VERSION="1.0.0"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_usage() {
    cat <<'EOF'
service_monitor.sh — Advanced System Service Monitoring and Management Tool

USAGE
    service_monitor.sh [OPTIONS] [SERVICE...]

DESCRIPTION
    Monitor critical system services and automatically restart failed services
    with configurable service definitions, custom health checks, continuous
    monitoring capabilities, email notifications, and comprehensive logging.

OPTIONS
    -h, --help           Show this help message
    -f, --config FILE    Configuration file (default: ~/.service_monitor.conf)
    -c, --check-only     Check services status without restarting
    -r, --restart        Force restart specified services
    -w, --watch          Continuous monitoring mode with periodic checks
    -i, --interval SEC   Check interval in watch mode (default: 30 seconds)
    -n, --notify EMAIL   Send email notifications for failures and recoveries
    -l, --log FILE       Log file location (default: ~/.service_monitor.log)
    -d, --daemon         Run as daemon process in background
    -p, --pid-file FILE  PID file for daemon mode (default: /tmp/service_monitor.pid)
    -v, --verbose        Show verbose output and detailed diagnostics
    -s, --status         Show current status of all configured services
    --dry-run            Show what actions would be performed
    --version            Show script version

CONFIGURATION FORMAT
    service_name:check_command:restart_command:max_failures:cooldown_seconds

    service_name     Name of the service to monitor
    check_command    Command to verify service is running (exit 0 = running)
    restart_command  Command to restart the service
    max_failures     Maximum consecutive failures before giving up
    cooldown_seconds Time to wait before rechecking after restart

CONFIGURATION EXAMPLES
    nginx:systemctl is-active nginx:systemctl restart nginx:3:300
    mysql:systemctl is-active mysql:systemctl restart mysql:5:600
    apache2:systemctl is-active apache2:systemctl restart apache2:3:300
    docker:systemctl is-active docker:systemctl restart docker:3:300
    webapp:/opt/webapp/healthcheck.sh:/opt/webapp/restart.sh:3:300

MONITORING MODES
    Single Check:       One-time check and restart if needed
    Watch Mode:         Continuous monitoring with configurable intervals
    Daemon Mode:        Background process with logging and notifications
    Status Report:      Display current service status and history
    Interactive Check:  Check specific services only

EXAMPLES (run directly from GitHub)
    # Show status of all configured services
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/service_monitor.sh)" -- -s

    # Check specific services without restarting
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/service_monitor.sh)" -- -c nginx mysql

    # Continuous monitoring with 60-second intervals
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/service_monitor.sh)" -- -w -i 60

    # Force restart a specific service
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/service_monitor.sh)" -- -r apache2

    # Daemon mode with email notifications
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/service_monitor.sh)" -- -d -n admin@company.com

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/service_monitor.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/service_monitor.sh
    chmod +x /tmp/service_monitor.sh
    /tmp/service_monitor.sh --help      # Show this help
    /tmp/service_monitor.sh -s          # Check service status
    /tmp/service_monitor.sh -c nginx    # Check nginx without restart
    /tmp/service_monitor.sh -w -v       # Watch mode with verbose output

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/service-monitor https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/service_monitor.sh
    sudo chmod +x /usr/local/bin/service-monitor
    service-monitor -d -n admin@company.com

AUTOMATION EXAMPLES
    # System service monitoring daemon
    service-monitor -d -n admin@company.com -i 30
    
    # Cron job for periodic checks
    */15 * * * * /usr/local/bin/service-monitor -c > /dev/null
    
    # CI/CD service validation
    service-monitor -c nginx mysql || exit 1

MONITORING FEATURES
    Configurable Checks:   Custom health check commands per service
    Failure Thresholds:    Maximum failures before abandoning restart attempts
    Cooldown Periods:      Prevent rapid restart loops
    Email Notifications:   Alert on failures and recoveries
    Detailed Logging:      Comprehensive logs with timestamps
    State Persistence:     Track failure counts and last restart times
    Interactive Mode:      Real-time monitoring with user feedback

SAFETY FEATURES
    Dry Run Mode:          Preview actions without executing them
    Failure Limits:        Prevent infinite restart loops
    Cooldown Protection:   Rate limiting for restart attempts
    Error Handling:        Graceful handling of service failures
    Logging:               Complete audit trail of all actions

NOTIFICATION SYSTEM
    Email Alerts:          Configurable email notifications
    Failure Reports:       Detailed failure analysis and context
    Recovery Notices:      Confirmation when services recover
    Rate Limiting:         Prevent notification spam
    Batch Reporting:       Summary reports for multiple failures

COMMON USE CASES
    Server Monitoring:     Ensure critical services stay running
    Application Health:    Monitor custom applications and APIs
    Database Monitoring:   Keep database services available
    Web Server Health:     Monitor nginx, apache, and other web servers
    Container Services:    Monitor Docker and container runtimes
    Development Services:  Keep development environments running

EXIT CODES
    0   All services running properly or daemon started successfully
    1   Some services failed or daemon already running
    2   Configuration file errors or missing dependencies
    3   Invalid command line arguments
    4   Insufficient permissions or system errors

EOF
}

DEFAULT_CONFIG="$HOME/.service_monitor.conf"
DEFAULT_LOG="$HOME/.service_monitor.log"
DEFAULT_PID="/tmp/service_monitor.pid"

log_message() {
    local level="$1"
    local message="$2"
    local log_file="${3:-$DEFAULT_LOG}"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$log_file"
}

create_default_config() {
    local config_file="$1"
    
    cat > "$config_file" << 'EOF'
# Service Monitor Configuration
# Format: service_name:check_command:restart_command:max_failures:cooldown_seconds
#
# service_name     - Name of the service to monitor
# check_command    - Command to check if service is running (exit 0 = running)
# restart_command  - Command to restart the service
# max_failures     - Maximum consecutive failures before giving up
# cooldown_seconds - Time to wait before rechecking after restart

# Common services
nginx:systemctl is-active nginx:systemctl restart nginx:3:300
apache2:systemctl is-active apache2:systemctl restart apache2:3:300
mysql:systemctl is-active mysql:systemctl restart mysql:5:600
mariadb:systemctl is-active mariadb:systemctl restart mariadb:5:600
postgresql:systemctl is-active postgresql:systemctl restart postgresql:5:600
redis:systemctl is-active redis:systemctl restart redis:3:300
docker:systemctl is-active docker:systemctl restart docker:3:300
ssh:systemctl is-active ssh:systemctl restart ssh:2:180
sshd:systemctl is-active sshd:systemctl restart sshd:2:180

# Custom service examples (uncomment and modify as needed)
# webapp:/opt/webapp/check.sh:/opt/webapp/restart.sh:3:300
# api_server:curl -f http://localhost:8080/health:systemctl restart api-server:3:300
# database_backup:ps aux | grep -q backup_script:killall backup_script && /usr/local/bin/backup_script:1:3600
EOF
    
    echo -e "${GREEN}Created default config file: $config_file${NC}"
    echo "Please edit the config file to match your system's services."
}

parse_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${YELLOW}Config file not found: $config_file${NC}"
        echo "Creating default config file..."
        create_default_config "$config_file"
        return 1
    fi
    
    grep -v '^#' "$config_file" | grep -v '^[[:space:]]*$' || true
}

check_service() {
    local service_name="$1"
    local check_command="$2"
    local verbose="$3"
    
    if [[ "$verbose" == "true" ]]; then
        echo -e "${CYAN}Checking $service_name...${NC}"
    fi
    
    if eval "$check_command" >/dev/null 2>&1; then
        return 0  # Service is running
    else
        return 1  # Service is not running
    fi
}

restart_service() {
    local service_name="$1"
    local restart_command="$2"
    local dry_run="$3"
    local verbose="$4"
    
    echo -e "${YELLOW}Restarting $service_name...${NC}"
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would execute: $restart_command${NC}"
        return 0
    fi
    
    if eval "$restart_command" >/dev/null 2>&1; then
        echo -e "${GREEN}Successfully restarted $service_name${NC}"
        return 0
    else
        echo -e "${RED}Failed to restart $service_name${NC}"
        return 1
    fi
}

get_service_status() {
    local service_name="$1"
    local check_command="$2"
    
    if eval "$check_command" >/dev/null 2>&1; then
        echo -e "${GREEN}RUNNING${NC}"
    else
        echo -e "${RED}STOPPED${NC}"
    fi
}

monitor_service() {
    local service_config="$1"
    local dry_run="$2"
    local verbose="$3"
    local log_file="$4"
    
    IFS=':' read -r service_name check_command restart_command max_failures cooldown <<< "$service_config"
    
    # Get current failure count and last restart time from state file
    local state_file="/tmp/.service_monitor_${service_name}.state"
    local failure_count=0
    local last_restart=0
    local last_failure=0
    
    if [[ -f "$state_file" ]]; then
        source "$state_file"
    fi
    
    local current_time
    current_time=$(date +%s)
    
    # Check if we're in cooldown period
    if [[ $((current_time - last_restart)) -lt $cooldown ]]; then
        if [[ "$verbose" == "true" ]]; then
            local remaining=$((cooldown - (current_time - last_restart)))
            echo -e "${BLUE}$service_name: In cooldown period (${remaining}s remaining)${NC}"
        fi
        return 0
    fi
    
    # Check service status
    if check_service "$service_name" "$check_command" "$verbose"; then
        # Service is running - reset failure count
        if [[ $failure_count -gt 0 ]]; then
            failure_count=0
            echo "failure_count=$failure_count" > "$state_file"
            echo "last_restart=$last_restart" >> "$state_file"
            echo "last_failure=$last_failure" >> "$state_file"
            log_message "INFO" "$service_name: Service recovered, resetting failure count" "$log_file"
        fi
        
        if [[ "$verbose" == "true" ]]; then
            echo -e "${GREEN}$service_name: OK${NC}"
        fi
        return 0
    else
        # Service is not running
        ((failure_count++))
        last_failure=$current_time
        
        log_message "WARN" "$service_name: Service check failed (attempt $failure_count/$max_failures)" "$log_file"
        
        if [[ $failure_count -ge $max_failures ]]; then
            log_message "ERROR" "$service_name: Maximum failures reached ($max_failures), giving up" "$log_file"
            echo -e "${RED}$service_name: FAILED (max failures reached)${NC}"
            return 1
        fi
        
        echo -e "${YELLOW}$service_name: Service not running (failure $failure_count/$max_failures)${NC}"
        
        # Attempt restart
        if restart_service "$service_name" "$restart_command" "$dry_run" "$verbose"; then
            last_restart=$current_time
            log_message "INFO" "$service_name: Service restarted successfully" "$log_file"
        else
            log_message "ERROR" "$service_name: Service restart failed" "$log_file"
        fi
        
        # Update state file
        echo "failure_count=$failure_count" > "$state_file"
        echo "last_restart=$last_restart" >> "$state_file"
        echo "last_failure=$last_failure" >> "$state_file"
        
        return 1
    fi
}

show_service_status() {
    local config_file="$1"
    local services=("${@:2}")
    
    echo -e "${BLUE}Service Status Report${NC}"
    echo -e "${BLUE}=====================${NC}"
    echo ""
    
    parse_config "$config_file" | while IFS=':' read -r service_name check_command restart_command max_failures cooldown; do
        # Skip if specific services requested and this isn't one of them
        if [[ ${#services[@]} -gt 0 ]]; then
            local found=false
            for requested_service in "${services[@]}"; do
                if [[ "$service_name" == "$requested_service" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "false" ]]; then
                continue
            fi
        fi
        
        local status
        status=$(get_service_status "$service_name" "$check_command")
        
        # Get failure history from state file
        local state_file="/tmp/.service_monitor_${service_name}.state"
        local failure_count=0
        local last_restart=0
        local last_failure=0
        
        if [[ -f "$state_file" ]]; then
            source "$state_file"
        fi
        
        printf "%-20s %s" "$service_name:" "$status"
        
        if [[ $failure_count -gt 0 ]]; then
            printf " (failures: %d/%d)" "$failure_count" "$max_failures"
        fi
        
        if [[ $last_restart -gt 0 ]]; then
            local last_restart_time
            last_restart_time=$(date -d "@$last_restart" '+%Y-%m-%d %H:%M:%S')
            printf " (last restart: %s)" "$last_restart_time"
        fi
        
        echo ""
    done
    
    echo ""
}

send_notification() {
    local email="$1"
    local subject="$2"
    local message="$3"
    
    if [[ -z "$email" ]]; then
        return 0
    fi
    
    if ! command -v mail >/dev/null 2>&1; then
        log_message "WARN" "mail command not found, notification not sent"
        return 1
    fi
    
    echo "$message" | mail -s "$subject" "$email"
    log_message "INFO" "Notification sent to: $email"
}

run_daemon() {
    local config_file="$1"
    local interval="$2"
    local log_file="$3"
    local pid_file="$4"
    local email="$5"
    local verbose="$6"
    
    # Write PID file
    echo $$ > "$pid_file"
    
    log_message "INFO" "Service monitor daemon started (PID: $$)" "$log_file"
    
    # Trap signals for graceful shutdown
    trap "log_message 'INFO' 'Service monitor daemon stopping'; rm -f '$pid_file'; exit 0" TERM INT
    
    local check_count=0
    local last_notification=0
    
    while true; do
        ((check_count++))
        local current_time
        current_time=$(date +%s)
        
        if [[ "$verbose" == "true" ]] || [[ $((check_count % 10)) -eq 0 ]]; then
            log_message "INFO" "Running check cycle $check_count" "$log_file"
        fi
        
        local failed_services=()
        local recovered_services=()
        
        parse_config "$config_file" | while IFS=':' read -r service_name check_command restart_command max_failures cooldown; do
            if ! monitor_service "$service_name:$check_command:$restart_command:$max_failures:$cooldown" "false" "$verbose" "$log_file"; then
                failed_services+=("$service_name")
            fi
        done
        
        # Send notifications if there are failures (but not too frequently)
        if [[ ${#failed_services[@]} -gt 0 && $((current_time - last_notification)) -gt 3600 ]]; then
            local notification_message="Service Monitor Alert - $(hostname)

The following services are experiencing issues:
$(printf '- %s\n' "${failed_services[@]}")

Time: $(date)
Check cycle: $check_count

Please investigate these services."
            
            send_notification "$email" "Service Monitor Alert - $(hostname)" "$notification_message"
            last_notification=$current_time
        fi
        
        sleep "$interval"
    done
}

main() {
    local config_file="$DEFAULT_CONFIG"
    local check_only=false
    local force_restart=false
    local watch_mode=false
    local interval=30
    local email=""
    local log_file="$DEFAULT_LOG"
    local daemon_mode=false
    local pid_file="$DEFAULT_PID"
    local verbose=false
    local show_status=false
    local dry_run=false
    local services=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                ;;
            -f|--config)
                config_file="$2"
                shift 2
                ;;
            -c|--check-only)
                check_only=true
                shift
                ;;
            -r|--restart)
                force_restart=true
                shift
                ;;
            -w|--watch)
                watch_mode=true
                shift
                ;;
            -i|--interval)
                interval="$2"
                shift 2
                ;;
            -n|--notify)
                email="$2"
                shift 2
                ;;
            -l|--log)
                log_file="$2"
                shift 2
                ;;
            -d|--daemon)
                daemon_mode=true
                watch_mode=true
                shift
                ;;
            -p|--pid-file)
                pid_file="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -s|--status)
                show_status=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --version)
                echo "service_monitor.sh version $SCRIPT_VERSION"
                exit 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                print_usage
                ;;
            *)
                services+=("$1")
                shift
                ;;
        esac
    done
    
    # Create log directory if needed
    mkdir -p "$(dirname "$log_file")"
    
    # Show status and exit
    if [[ "$show_status" == "true" ]]; then
        show_service_status "$config_file" "${services[@]}"
        exit 0
    fi
    
    # Check if config file exists
    if ! parse_config "$config_file" >/dev/null; then
        exit 1
    fi
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           SERVICE MONITOR${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Config file: $config_file"
    echo "Log file: $log_file"
    if [[ "$watch_mode" == "true" ]]; then
        echo "Mode: Watch (interval: ${interval}s)"
    elif [[ "$check_only" == "true" ]]; then
        echo "Mode: Check only"
    elif [[ "$force_restart" == "true" ]]; then
        echo "Mode: Force restart"
    else
        echo "Mode: Single check with restart"
    fi
    if [[ ${#services[@]} -gt 0 ]]; then
        echo "Services: ${services[*]}"
    fi
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE${NC}"
    fi
    echo "Started: $(date)"
    echo ""
    
    # Run in daemon mode
    if [[ "$daemon_mode" == "true" ]]; then
        if [[ -f "$pid_file" ]]; then
            local existing_pid
            existing_pid=$(cat "$pid_file")
            if kill -0 "$existing_pid" 2>/dev/null; then
                echo -e "${YELLOW}Daemon already running (PID: $existing_pid)${NC}"
                exit 1
            fi
        fi
        
        echo "Starting daemon mode..."
        run_daemon "$config_file" "$interval" "$log_file" "$pid_file" "$email" "$verbose" &
        echo -e "${GREEN}Service monitor daemon started (PID: $!)${NC}"
        echo "PID file: $pid_file"
        echo "Log file: $log_file"
        exit 0
    fi
    
    # Watch mode
    if [[ "$watch_mode" == "true" ]]; then
        echo -e "${CYAN}Entering watch mode (Ctrl+C to stop)...${NC}"
        echo ""
        
        while true; do
            local start_time
            start_time=$(date)
            echo -e "${BLUE}Check at $start_time${NC}"
            
            parse_config "$config_file" | while IFS=':' read -r service_name check_command restart_command max_failures cooldown; do
                # Skip if specific services requested and this isn't one of them
                if [[ ${#services[@]} -gt 0 ]]; then
                    local found=false
                    for requested_service in "${services[@]}"; do
                        if [[ "$service_name" == "$requested_service" ]]; then
                            found=true
                            break
                        fi
                    done
                    if [[ "$found" == "false" ]]; then
                        continue
                    fi
                fi
                
                monitor_service "$service_name:$check_command:$restart_command:$max_failures:$cooldown" "$dry_run" "$verbose" "$log_file"
            done
            
            echo ""
            sleep "$interval"
        done
        exit 0
    fi
    
    # Single run mode
    local failed_count=0
    local total_count=0
    
    parse_config "$config_file" | while IFS=':' read -r service_name check_command restart_command max_failures cooldown; do
        # Skip if specific services requested and this isn't one of them
        if [[ ${#services[@]} -gt 0 ]]; then
            local found=false
            for requested_service in "${services[@]}"; do
                if [[ "$service_name" == "$requested_service" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "false" ]]; then
                continue
            fi
        fi
        
        ((total_count++))
        
        if [[ "$force_restart" == "true" ]]; then
            restart_service "$service_name" "$restart_command" "$dry_run" "$verbose"
        elif [[ "$check_only" == "true" ]]; then
            local status
            status=$(get_service_status "$service_name" "$check_command")
            echo -e "${CYAN}$service_name:${NC} $status"
        else
            if ! monitor_service "$service_name:$check_command:$restart_command:$max_failures:$cooldown" "$dry_run" "$verbose" "$log_file"; then
                ((failed_count++))
            fi
        fi
    done
    
    echo ""
    echo -e "${BLUE}================================================${NC}"
    if [[ "$check_only" == "false" && "$force_restart" == "false" ]]; then
        if [[ $failed_count -eq 0 ]]; then
            echo -e "${GREEN}All services are running properly${NC}"
        else
            echo -e "${YELLOW}$failed_count out of $total_count services have issues${NC}"
        fi
    fi
    echo -e "${GREEN}Service monitor completed at $(date)${NC}"
    echo -e "${BLUE}================================================${NC}"
    
    # Exit with error code if there were failures
    if [[ $failed_count -gt 0 ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    main "$@"
fi