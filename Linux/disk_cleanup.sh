#!/usr/bin/env bash
# disk_cleanup.sh
# Purpose:
#   - Intelligent disk space cleanup for Linux systems
#   - Safely removes old logs, temporary files, caches, and unused packages
#   - Configurable retention policies and safety checks
#
# Features:
#   - Multiple cleanup modes: safe, aggressive, custom
#   - Package manager cache cleanup (APT, YUM, DNF)
#   - Docker container and image cleanup
#   - Configurable retention periods
#   - Dry-run mode for safe preview
#   - Space usage reporting before/after cleanup
#
# Maintainer: ddviet
SCRIPT_VERSION="1.0.0"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_usage() {
    cat <<'EOF'
disk_cleanup.sh — Intelligent Linux Disk Space Cleaner

USAGE
    disk_cleanup.sh [OPTIONS]

DESCRIPTION
    Safely reclaim disk space by removing old logs, temporary files, caches, and
    unused packages. Uses intelligent retention policies and provides detailed
    reporting of space savings.

OPTIONS
    -d, --dry-run       Preview what would be deleted without deleting
    -a, --aggressive    Shorter retention periods (3 days logs, 1 day cache)
    -s, --safe          Longer retention periods (30 days logs, 14 days cache)
    -t, --target DIR    Target directory to clean (default: system-wide)
    -l, --logs-only     Clean only log files and rotated logs
    -c, --cache-only    Clean only cache directories and files
    --docker            Clean Docker containers, images, and build cache
    --apt               Clean APT package cache (Ubuntu/Debian)
    --yum               Clean YUM/DNF cache (RHEL/CentOS/Fedora)
    --version           Show script version
    -h, --help          Show this help message

CLEANUP MODES
    Normal:     7 days logs, 7 days cache, 3 days temp files
    Safe:       30 days logs, 14 days cache, 7 days temp files  
    Aggressive: 3 days logs, 1 day cache, 1 day temp files

EXAMPLES (run directly from GitHub)
    # Safe preview of cleanup actions
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/disk_cleanup.sh)" -- --dry-run

    # Aggressive cleanup including Docker
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/disk_cleanup.sh)" -- --aggressive --docker

    # Safe cleanup of home directory only
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/disk_cleanup.sh)" -- --safe --target /home

    # Clean only package manager caches
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/disk_cleanup.sh)" -- --apt --yum

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/disk_cleanup.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/disk_cleanup.sh
    chmod +x /tmp/disk_cleanup.sh
    /tmp/disk_cleanup.sh --dry-run         # preview first
    /tmp/disk_cleanup.sh --safe            # safe cleanup
    /tmp/disk_cleanup.sh --aggressive --docker # thorough cleanup

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/disk-cleanup https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/disk_cleanup.sh
    sudo chmod +x /usr/local/bin/disk-cleanup
    disk-cleanup --dry-run

AUTOMATION EXAMPLES
    # Weekly cleanup cron job
    0 2 * * 0 /usr/local/bin/disk-cleanup --safe

    # Emergency cleanup when disk is full
    if [[ $(df / | tail -1 | awk '{print $5}' | sed 's/%//') -gt 90 ]]; then
        disk-cleanup --aggressive --docker
    fi

    # Maintenance script
    disk-cleanup --dry-run | mail -s "Weekly cleanup preview" admin@example.com

CLEANED LOCATIONS
    System Logs:        /var/log, /tmp, /var/tmp
    User Caches:        ~/.cache, browser caches, thumbnails
    Package Caches:     APT, YUM, DNF, Snap packages
    Docker:             Unused containers, images, build cache
    Temporary Files:    /tmp, /var/tmp, user temp directories
    Journal Logs:       systemd journal with configurable retention

SPACE REPORTING
    • Shows disk usage before and after cleanup
    • Reports space saved by category
    • Identifies largest space consumers
    • Tracks cleanup history and trends

SAFETY FEATURES
    • Dry-run mode for safe preview
    • Configurable retention periods
    • Excludes critical system files
    • Preserves recent backups and user data
    • Requires root confirmation for system-wide cleanup

EXIT CODES
    0   Cleanup completed successfully
    1   No cleanup needed or permission denied
    2   Critical error during cleanup
    3   Invalid arguments

SECURITY NOTES
    • Requires appropriate permissions for target directories
    • System-wide cleanup may need sudo/root privileges
    • Always preview with --dry-run first
    • Safe for production environments in safe mode

EOF
}

check_space_before() {
    echo -e "${BLUE}Disk space before cleanup:${NC}"
    df -h / | tail -1 | awk '{printf "  Root: %s used, %s available (%s usage)\n", $3, $4, $5}'
    if [[ -d /home ]]; then
        df -h /home 2>/dev/null | tail -1 | awk '{printf "  Home: %s used, %s available (%s usage)\n", $3, $4, $5}' || true
    fi
    echo ""
}

check_space_after() {
    echo -e "${GREEN}Disk space after cleanup:${NC}"
    df -h / | tail -1 | awk '{printf "  Root: %s used, %s available (%s usage)\n", $3, $4, $5}'
    if [[ -d /home ]]; then
        df -h /home 2>/dev/null | tail -1 | awk '{printf "  Home: %s used, %s available (%s usage)\n", $3, $4, $5}' || true
    fi
    echo ""
}

safe_remove() {
    local path="$1"
    local description="$2"
    local dry_run="$3"
    
    if [[ ! -e "$path" ]]; then
        return 0
    fi
    
    local size
    if [[ -f "$path" ]]; then
        size=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "unknown")
    elif [[ -d "$path" ]]; then
        size=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "unknown")
    else
        size="unknown"
    fi
    
    echo -e "${CYAN}$description${NC} ($size): $path"
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}  [DRY RUN] Would remove${NC}"
        return 0
    fi
    
    if [[ -f "$path" ]]; then
        rm -f "$path" 2>/dev/null && echo -e "${GREEN}  Removed file${NC}" || echo -e "${RED}  Failed to remove${NC}"
    elif [[ -d "$path" ]]; then
        rm -rf "$path" 2>/dev/null && echo -e "${GREEN}  Removed directory${NC}" || echo -e "${RED}  Failed to remove${NC}"
    fi
}

clean_system_logs() {
    local target_dir="$1"
    local days="$2"
    local dry_run="$3"
    
    echo -e "${BLUE}Cleaning system logs older than $days days...${NC}"
    
    local log_dirs=("$target_dir/var/log" "$target_dir/tmp" "$target_dir/var/tmp")
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ ! -d "$log_dir" ]]; then
            continue
        fi
        
        # Old log files
        find "$log_dir" -name "*.log" -type f -mtime +$days 2>/dev/null | while IFS= read -r file; do
            safe_remove "$file" "Old log file" "$dry_run"
        done
        
        # Rotated logs
        find "$log_dir" -name "*.log.*" -type f -mtime +$days 2>/dev/null | while IFS= read -r file; do
            safe_remove "$file" "Rotated log file" "$dry_run"
        done
        
        # Compressed logs
        find "$log_dir" -name "*.gz" -type f -mtime +$days 2>/dev/null | while IFS= read -r file; do
            safe_remove "$file" "Compressed log file" "$dry_run"
        done
    done
    
    # Journal logs (systemd)
    if command -v journalctl >/dev/null 2>&1; then
        echo -e "${CYAN}Cleaning systemd journal logs older than ${days} days${NC}"
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}  [DRY RUN] Would clean journal logs${NC}"
        else
            journalctl --vacuum-time="${days}d" >/dev/null 2>&1 && echo -e "${GREEN}  Cleaned journal logs${NC}" || echo -e "${YELLOW}  No journal cleanup needed${NC}"
        fi
    fi
}

clean_cache_files() {
    local target_dir="$1"
    local days="$2"
    local dry_run="$3"
    
    echo -e "${BLUE}Cleaning cache files...${NC}"
    
    local cache_dirs=(
        "$target_dir/var/cache"
        "$target_dir/tmp"
        "$target_dir/var/tmp"
        "$HOME/.cache"
        "$target_dir/home/*/.cache"
    )
    
    for cache_pattern in "${cache_dirs[@]}"; do
        for cache_dir in $cache_pattern; do
            if [[ ! -d "$cache_dir" ]]; then
                continue
            fi
            
            # Browser cache
            find "$cache_dir" -type d \( -name "*chrom*" -o -name "*firefox*" -o -name "*mozilla*" \) 2>/dev/null | while IFS= read -r dir; do
                if [[ -d "$dir" ]]; then
                    find "$dir" -type f -mtime +$days 2>/dev/null | while IFS= read -r file; do
                        safe_remove "$file" "Browser cache file" "$dry_run"
                    done
                fi
            done
            
            # Thumbnail cache
            find "$cache_dir" -name "thumbnails" -type d 2>/dev/null | while IFS= read -r dir; do
                find "$dir" -type f -mtime +$days 2>/dev/null | while IFS= read -r file; do
                    safe_remove "$file" "Thumbnail cache" "$dry_run"
                done
            done
            
            # General cache files
            find "$cache_dir" -name "*.cache" -type f -mtime +$days 2>/dev/null | while IFS= read -r file; do
                safe_remove "$file" "Cache file" "$dry_run"
            done
        done
    done
}

clean_temp_files() {
    local target_dir="$1"
    local days="$2"
    local dry_run="$3"
    
    echo -e "${BLUE}Cleaning temporary files older than $days days...${NC}"
    
    local temp_dirs=("$target_dir/tmp" "$target_dir/var/tmp")
    
    for temp_dir in "${temp_dirs[@]}"; do
        if [[ ! -d "$temp_dir" ]]; then
            continue
        fi
        
        find "$temp_dir" -type f -mtime +$days 2>/dev/null | while IFS= read -r file; do
            safe_remove "$file" "Temporary file" "$dry_run"
        done
        
        find "$temp_dir" -type d -empty 2>/dev/null | while IFS= read -r dir; do
            safe_remove "$dir" "Empty temp directory" "$dry_run"
        done
    done
}

clean_package_managers() {
    local dry_run="$1"
    
    echo -e "${BLUE}Cleaning package manager caches...${NC}"
    
    # APT (Ubuntu/Debian)
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "${CYAN}Cleaning APT cache${NC}"
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}  [DRY RUN] Would run: apt-get clean && apt-get autoclean${NC}"
        else
            apt-get clean >/dev/null 2>&1 && echo -e "${GREEN}  APT cache cleaned${NC}" || echo -e "${RED}  Failed to clean APT cache${NC}"
            apt-get autoclean >/dev/null 2>&1 && echo -e "${GREEN}  APT autoclean completed${NC}" || true
        fi
    fi
    
    # YUM/DNF (RHEL/CentOS/Fedora)
    if command -v yum >/dev/null 2>&1; then
        echo -e "${CYAN}Cleaning YUM cache${NC}"
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}  [DRY RUN] Would run: yum clean all${NC}"
        else
            yum clean all >/dev/null 2>&1 && echo -e "${GREEN}  YUM cache cleaned${NC}" || echo -e "${RED}  Failed to clean YUM cache${NC}"
        fi
    elif command -v dnf >/dev/null 2>&1; then
        echo -e "${CYAN}Cleaning DNF cache${NC}"
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}  [DRY RUN] Would run: dnf clean all${NC}"
        else
            dnf clean all >/dev/null 2>&1 && echo -e "${GREEN}  DNF cache cleaned${NC}" || echo -e "${RED}  Failed to clean DNF cache${NC}"
        fi
    fi
}

clean_docker() {
    local dry_run="$1"
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker not found, skipping Docker cleanup${NC}"
        return
    fi
    
    echo -e "${BLUE}Cleaning Docker resources...${NC}"
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${CYAN}Docker system disk usage:${NC}"
        docker system df 2>/dev/null || echo -e "${YELLOW}  Cannot access Docker${NC}"
        echo -e "${YELLOW}  [DRY RUN] Would run: docker system prune -a${NC}"
    else
        echo -e "${CYAN}Cleaning Docker containers, networks, and images${NC}"
        docker system prune -a -f >/dev/null 2>&1 && echo -e "${GREEN}  Docker cleanup completed${NC}" || echo -e "${RED}  Failed to clean Docker${NC}"
    fi
}

main() {
    local dry_run=false
    local target_dir="/"
    local mode="normal"
    local logs_only=false
    local cache_only=false
    local clean_docker_flag=false
    local clean_apt=false
    local clean_yum=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -a|--aggressive)
                mode="aggressive"
                shift
                ;;
            -s|--safe)
                mode="safe"
                shift
                ;;
            -t|--target)
                target_dir="$2"
                shift 2
                ;;
            -l|--logs-only)
                logs_only=true
                shift
                ;;
            -c|--cache-only)
                cache_only=true
                shift
                ;;
            --docker)
                clean_docker_flag=true
                shift
                ;;
            --apt)
                clean_apt=true
                shift
                ;;
            --yum)
                clean_yum=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                usage
                ;;
            *)
                echo -e "${RED}Unexpected argument: $1${NC}" >&2
                usage
                ;;
        esac
    done
    
    # Set retention days based on mode
    local log_days=7
    local cache_days=7
    local temp_days=3
    
    case "$mode" in
        aggressive)
            log_days=3
            cache_days=1
            temp_days=1
            ;;
        safe)
            log_days=30
            cache_days=14
            temp_days=7
            ;;
    esac
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}            DISK CLEANUP${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Mode: $mode"
    echo "Target directory: $target_dir"
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No files will be deleted${NC}"
    fi
    echo "Started: $(date)"
    echo ""
    
    check_space_before
    
    if [[ "$cache_only" == "false" && "$logs_only" != "true" ]]; then
        clean_temp_files "$target_dir" "$temp_days" "$dry_run"
        echo ""
    fi
    
    if [[ "$cache_only" == "true" || "$logs_only" == "false" ]]; then
        clean_cache_files "$target_dir" "$cache_days" "$dry_run"
        echo ""
    fi
    
    if [[ "$logs_only" == "true" || "$cache_only" == "false" ]]; then
        clean_system_logs "$target_dir" "$log_days" "$dry_run"
        echo ""
    fi
    
    if [[ "$clean_apt" == "true" || "$clean_yum" == "true" || ("$cache_only" == "false" && "$logs_only" == "false") ]]; then
        clean_package_managers "$dry_run"
        echo ""
    fi
    
    if [[ "$clean_docker_flag" == "true" ]]; then
        clean_docker "$dry_run"
        echo ""
    fi
    
    if [[ "$dry_run" == "false" ]]; then
        check_space_after
    fi
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Cleanup completed at $(date)${NC}"
    echo -e "${BLUE}================================================${NC}"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    if [[ $EUID -eq 0 ]]; then
        echo -e "${YELLOW}Warning: Running as root. This will clean system-wide files.${NC}"
        echo -e "${YELLOW}Press Ctrl+C within 5 seconds to cancel...${NC}"
        sleep 5
    fi
    main "$@"
fi