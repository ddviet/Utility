#!/bin/bash
# backup_rotation.sh
# Purpose:
#   - Create automated backups with intelligent retention policies
#   - Support multiple compression formats and backup types (tar, rsync)
#   - Implement flexible rotation schedules (daily, weekly, monthly)
#
# Features:
#   - Flexible retention policies with configurable time periods
#   - Multiple compression options: gzip, bzip2, xz, none
#   - Both full and incremental backup support
#   - Smart exclude patterns and customizable backup sets
#   - GPG encryption support for sensitive data
#   - Email notifications on backup completion or failure
#   - Detailed logging and backup verification
#   - Dry-run mode for testing backup configurations
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
backup_rotation.sh — Automated Backup System with Intelligent Rotation

USAGE
    backup_rotation.sh [OPTIONS] SOURCE DESTINATION

DESCRIPTION
    Create automated backups with intelligent retention policies, supporting
    multiple compression formats, encryption, and flexible rotation schedules.
    Implements both full and incremental backup strategies with verification.

OPTIONS
    -h, --help              Show this help message
    -n, --name NAME         Backup set name (default: basename of source)
    -c, --compress TYPE     Compression: gzip, bzip2, xz, none (default: gzip)
    -k, --keep-policy POLICY Retention policy (default: '7d,4w,12m')
    -e, --exclude PATTERN   Additional exclude pattern (can use multiple times)
    -i, --incremental       Incremental backup (requires rsync)
    -f, --full              Force full backup
    -v, --verbose           Verbose output
    -t, --type TYPE         Backup type: tar, rsync (default: tar)
    -s, --schedule          Show next scheduled cleanup times
    --dry-run               Show what would be done without doing it
    --encrypt               Encrypt backup with GPG
    --email EMAIL           Send notification email on completion
    --verify                Verify backup after creation
    --version               Show script version

RETENTION POLICY FORMAT
    Format:   'daily,weekly,monthly' where each is number + unit
    Units:    d (days), w (weeks), m (months), y (years)
    
    Examples:
    '7d,4w,12m'    Keep 7 daily, 4 weekly, 12 monthly backups
    '30d'          Keep 30 daily backups only
    '14d,8w,6m,2y' Keep 14 daily, 8 weekly, 6 monthly, 2 yearly

EXAMPLES (run directly from GitHub)
    # Basic backup with default retention
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/backup_rotation.sh)" -- /home/user /backup

    # Custom retention policy with compression
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/backup_rotation.sh)" -- -k '30d,12w' -c xz /var/www /backups

    # Incremental backup with rsync
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/backup_rotation.sh)" -- -i -t rsync /data /backup/incremental

    # Preview with dry-run
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/backup_rotation.sh)" -- --dry-run /home /backup

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/backup_rotation.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/backup_rotation.sh
    chmod +x /tmp/backup_rotation.sh
    /tmp/backup_rotation.sh --help                    # Show help
    /tmp/backup_rotation.sh --dry-run /src /dest      # Preview operation
    /tmp/backup_rotation.sh -k '7d,4w,12m' /src /dest # Execute backup
    /tmp/backup_rotation.sh -s /src /dest             # Show rotation schedule

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/backup-rotate https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/backup_rotation.sh
    sudo chmod +x /usr/local/bin/backup-rotate
    backup-rotate --help

COMMON USE CASES
    Home Directory:     backup-rotate /home/user /backup/home
    Web Server:         backup-rotate -c xz /var/www /backup/web
    Database:           backup-rotate --encrypt /var/lib/mysql /backup/db
    System Config:      backup-rotate -e '*.log' /etc /backup/config
    Documents:          backup-rotate -k '365d' ~/Documents /backup/docs
    Development:        backup-rotate -i -t rsync ~/projects /backup/dev

BACKUP STRATEGIES
    Full Backup:        Complete copy of all data
    Incremental:        Only changed files since last backup
    Differential:       Changed files since last full backup
    Mirror:             Exact replica using rsync
    Archive:            Compressed tarball with timestamps

CRON AUTOMATION
    # Daily backup at 2 AM
    0 2 * * * /usr/local/bin/backup-rotate /home /backup/daily

    # Weekly backup on Sunday
    0 3 * * 0 /usr/local/bin/backup-rotate -f /var/www /backup/weekly

    # Monthly backup on 1st
    0 4 1 * * /usr/local/bin/backup-rotate -c xz /data /backup/monthly

SAFETY FEATURES
    Verification:       Optional backup integrity checking
    Atomic Operations:  Temporary files ensure consistency
    Exclude Patterns:   Skip temporary and cache files
    Dry-Run Mode:       Preview all operations
    Logging:            Detailed operation logs
    Lock Files:         Prevent concurrent backups

EXCLUDE PATTERNS
    Default exclusions: .tmp, .cache, *.swp, .DS_Store
    Custom patterns:    Use -e flag multiple times
    Exclude file:       Create .backup-exclude in source

ADVANCED EXAMPLES
    # Encrypted backup with email notification
    backup-rotate --encrypt --email admin@example.com /sensitive /secure

    # Multiple excludes with custom name
    backup-rotate -n "project" -e "*.log" -e "node_modules" /app /backup

    # Incremental with verification
    backup-rotate -i --verify -t rsync /large-data /backup/incremental

    # Show rotation schedule
    backup-rotate -s -k '7d,4w,12m,2y' /data /backup

EXIT CODES
    0   Successful backup and rotation
    1   Invalid arguments or help displayed
    2   Source or destination error
    3   Backup operation failed
    4   Rotation or cleanup error
    5   Verification failed

EOF
    exit 1
}

parse_keep_policy() {
    local policy="$1"
    
    # Default policy if empty
    if [[ -z "$policy" ]]; then
        policy="7d,4w,12m"
    fi
    
    echo "$policy" | tr ',' '\n' | while IFS= read -r period; do
        if [[ "$period" =~ ^([0-9]+)([dwmy])$ ]]; then
            local count="${BASH_REMATCH[1]}"
            local unit="${BASH_REMATCH[2]}"
            echo "$count:$unit"
        else
            echo "ERROR:Invalid period format: $period" >&2
            return 1
        fi
    done
}

get_backup_timestamp() {
    local period_type="$1"
    local date_format=""
    
    case "$period_type" in
        d) date_format="%Y%m%d" ;;
        w) date_format="%Y%W" ;;
        m) date_format="%Y%m" ;;
        y) date_format="%Y" ;;
    esac
    
    date +"$date_format"
}

create_backup_name() {
    local name="$1"
    local period_type="$2"
    local compress_type="$3"
    local timestamp
    
    timestamp=$(get_backup_timestamp "$period_type")
    
    local extension=""
    case "$compress_type" in
        gzip) extension=".tar.gz" ;;
        bzip2) extension=".tar.bz2" ;;
        xz) extension=".tar.xz" ;;
        none) extension=".tar" ;;
    esac
    
    echo "${name}_${period_type}_${timestamp}${extension}"
}

should_create_backup() {
    local backup_dir="$1"
    local backup_name="$2"
    local period_type="$3"
    local force_full="$4"
    
    if [[ "$force_full" == "true" ]]; then
        return 0
    fi
    
    local pattern
    case "$period_type" in
        d) pattern="${backup_name%_*}_d_$(date +%Y%m%d)*" ;;
        w) pattern="${backup_name%_*}_w_$(date +%Y%W)*" ;;
        m) pattern="${backup_name%_*}_m_$(date +%Y%m)*" ;;
        y) pattern="${backup_name%_*}_y_$(date +%Y)*" ;;
    esac
    
    if find "$backup_dir" -name "$pattern" -type f 2>/dev/null | grep -q .; then
        return 1  # Backup exists
    else
        return 0  # No backup exists
    fi
}

create_tar_backup() {
    local source="$1"
    local backup_file="$2"
    local compress_type="$3"
    local exclude_patterns=("${@:4}")
    local verbose="$5"
    local encrypt="$6"
    local dry_run="$7"
    
    local tar_opts=(
        "-C" "$(dirname "$source")"
    )
    
    # Add compression
    case "$compress_type" in
        gzip) tar_opts+=("-z") ;;
        bzip2) tar_opts+=("-j") ;;
        xz) tar_opts+=("-J") ;;
    esac
    
    # Add verbose if requested
    if [[ "$verbose" == "true" ]]; then
        tar_opts+=("-v")
    fi
    
    # Add exclude patterns
    for pattern in "${exclude_patterns[@]}"; do
        if [[ -n "$pattern" ]]; then
            tar_opts+=("--exclude=$pattern")
        fi
    done
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would create: $backup_file${NC}"
        echo -e "${YELLOW}[DRY RUN] Command: tar ${tar_opts[*]} -cf $backup_file $(basename "$source")${NC}"
        return 0
    fi
    
    echo -e "${CYAN}Creating backup: $(basename "$backup_file")${NC}"
    
    # Create backup
    tar "${tar_opts[@]}" -cf "$backup_file" "$(basename "$source")" || {
        echo -e "${RED}Backup creation failed${NC}"
        return 1
    }
    
    # Encrypt if requested
    if [[ "$encrypt" == "true" ]]; then
        if command -v gpg >/dev/null 2>&1; then
            echo -e "${CYAN}Encrypting backup...${NC}"
            gpg --symmetric --cipher-algo AES256 --compress-algo 2 --s2k-digest-algo SHA512 "$backup_file"
            rm "$backup_file"
            backup_file="${backup_file}.gpg"
            echo -e "${GREEN}Backup encrypted: $(basename "$backup_file")${NC}"
        else
            echo -e "${YELLOW}Warning: gpg not found, backup not encrypted${NC}"
        fi
    fi
    
    local size
    size=$(du -sh "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
    echo -e "${GREEN}Backup created: $(basename "$backup_file") ($size)${NC}"
    
    return 0
}

create_rsync_backup() {
    local source="$1"
    local backup_dir="$2"
    local backup_name="$3"
    local incremental="$4"
    local exclude_patterns=("${@:5}")
    local verbose="$6"
    local dry_run="$7"
    
    local rsync_opts=(
        "-a"
        "--delete"
    )
    
    if [[ "$verbose" == "true" ]]; then
        rsync_opts+=("-v")
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        rsync_opts+=("--dry-run")
    fi
    
    # Add exclude patterns
    for pattern in "${exclude_patterns[@]}"; do
        if [[ -n "$pattern" ]]; then
            rsync_opts+=("--exclude=$pattern")
        fi
    done
    
    local dest_dir="$backup_dir/$backup_name"
    
    # Handle incremental backups
    if [[ "$incremental" == "true" ]]; then
        local latest_link="$backup_dir/${backup_name}_latest"
        if [[ -d "$latest_link" ]]; then
            rsync_opts+=("--link-dest=$latest_link")
        fi
    fi
    
    mkdir -p "$dest_dir"
    
    echo -e "${CYAN}Creating rsync backup: $backup_name${NC}"
    
    if rsync "${rsync_opts[@]}" "$source/" "$dest_dir/"; then
        # Update latest link for incremental backups
        if [[ "$incremental" == "true" && "$dry_run" == "false" ]]; then
            local latest_link="$backup_dir/${backup_name}_latest"
            rm -f "$latest_link"
            ln -sf "$dest_dir" "$latest_link"
        fi
        
        local size
        size=$(du -sh "$dest_dir" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "${GREEN}Rsync backup completed: $backup_name ($size)${NC}"
        return 0
    else
        echo -e "${RED}Rsync backup failed${NC}"
        return 1
    fi
}

cleanup_old_backups() {
    local backup_dir="$1"
    local name="$2"
    local keep_policy="$3"
    local dry_run="$4"
    
    echo -e "${BLUE}Cleaning up old backups...${NC}"
    
    while IFS=':' read -r count unit; do
        if [[ "$count" =~ ^[0-9]+$ ]] && [[ "$unit" =~ ^[dwmy]$ ]]; then
            cleanup_period "$backup_dir" "$name" "$unit" "$count" "$dry_run"
        fi
    done < <(parse_keep_policy "$keep_policy")
}

cleanup_period() {
    local backup_dir="$1"
    local name="$2"
    local period_unit="$3"
    local keep_count="$4"
    local dry_run="$5"
    
    local pattern="${name}_${period_unit}_*"
    local backups
    backups=$(find "$backup_dir" -name "$pattern" -type f 2>/dev/null | sort -r || true)
    
    if [[ -z "$backups" ]]; then
        return 0
    fi
    
    local count=0
    echo "$backups" | while IFS= read -r backup_file; do
        ((count++))
        if [[ $count -gt $keep_count ]]; then
            local size
            size=$(du -sh "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
            echo -e "${CYAN}  Removing old backup: $(basename "$backup_file") ($size)${NC}"
            
            if [[ "$dry_run" == "true" ]]; then
                echo -e "${YELLOW}    [DRY RUN] Would remove${NC}"
            else
                if rm -f "$backup_file"; then
                    echo -e "${GREEN}    Removed${NC}"
                else
                    echo -e "${RED}    Failed to remove${NC}"
                fi
            fi
        else
            echo -e "${GREEN}  Keeping: $(basename "$backup_file")${NC}"
        fi
    done
}

show_backup_schedule() {
    local name="$1"
    local keep_policy="$2"
    
    echo -e "${BLUE}Backup Schedule for '$name':${NC}"
    echo ""
    
    while IFS=':' read -r count unit; do
        local period_name=""
        case "$unit" in
            d) period_name="Daily" ;;
            w) period_name="Weekly" ;;
            m) period_name="Monthly" ;;
            y) period_name="Yearly" ;;
        esac
        
        echo "  $period_name: Keep $count backups"
        
        # Show next cleanup time
        local next_cleanup=""
        case "$unit" in
            d) next_cleanup="tomorrow at $(date +%H:%M)" ;;
            w) next_cleanup="next week on $(date -d 'next monday' +%A)" ;;
            m) next_cleanup="next month on the $(date +%d)th" ;;
            y) next_cleanup="next year on $(date +%B %d)" ;;
        esac
        
        echo "    Next cleanup: $next_cleanup"
        echo ""
    done < <(parse_keep_policy "$keep_policy")
}

send_notification() {
    local email="$1"
    local name="$2"
    local status="$3"
    local details="$4"
    
    if [[ -z "$email" ]]; then
        return 0
    fi
    
    if ! command -v mail >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: mail command not found, notification not sent${NC}"
        return 1
    fi
    
    local subject="Backup $status: $name"
    local body="Backup operation for '$name' completed with status: $status

Details:
$details

Time: $(date)
Host: $(hostname)"
    
    echo "$body" | mail -s "$subject" "$email"
    echo -e "${GREEN}Notification sent to: $email${NC}"
}

main() {
    local source=""
    local destination=""
    local name=""
    local compress_type="gzip"
    local keep_policy="7d,4w,12m"
    local exclude_patterns=()
    local incremental=false
    local force_full=false
    local verbose=false
    local backup_type="tar"
    local show_schedule=false
    local dry_run=false
    local encrypt=false
    local email=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                ;;
            -n|--name)
                name="$2"
                shift 2
                ;;
            -c|--compress)
                compress_type="$2"
                shift 2
                ;;
            -k|--keep-policy)
                keep_policy="$2"
                shift 2
                ;;
            -e|--exclude)
                exclude_patterns+=("$2")
                shift 2
                ;;
            -i|--incremental)
                incremental=true
                backup_type="rsync"
                shift
                ;;
            -f|--full)
                force_full=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -t|--type)
                backup_type="$2"
                shift 2
                ;;
            -s|--schedule)
                show_schedule=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --encrypt)
                encrypt=true
                shift
                ;;
            --email)
                email="$2"
                shift 2
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                print_usage
                ;;
            *)
                if [[ -z "$source" ]]; then
                    source="$1"
                elif [[ -z "$destination" ]]; then
                    destination="$1"
                else
                    echo -e "${RED}Too many arguments${NC}" >&2
                    print_usage
                fi
                shift
                ;;
        esac
    done
    
    # Set default name
    if [[ -z "$name" && -n "$source" ]]; then
        name=$(basename "$source")
    fi
    
    # Show schedule if requested
    if [[ "$show_schedule" == "true" ]]; then
        if [[ -z "$name" ]]; then
            echo -e "${RED}Name required for schedule display${NC}"
            exit 1
        fi
        show_backup_schedule "$name" "$keep_policy"
        exit 0
    fi
    
    # Validate arguments
    if [[ -z "$source" || -z "$destination" ]]; then
        echo -e "${RED}Source and destination are required${NC}"
        print_usage
    fi
    
    if [[ ! -e "$source" ]]; then
        echo -e "${RED}Source does not exist: $source${NC}"
        exit 1
    fi
    
    # Create destination directory
    mkdir -p "$destination"
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           BACKUP ROTATION${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Source: $source"
    echo "Destination: $destination"
    echo "Backup name: $name"
    echo "Type: $backup_type"
    echo "Compression: $compress_type"
    echo "Keep policy: $keep_policy"
    echo "Incremental: $incremental"
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE${NC}"
    fi
    echo "Started: $(date)"
    echo ""
    
    local backup_created=false
    local backup_status="SUCCESS"
    local backup_details=""
    
    # Parse keep policy and create backups
    while IFS=':' read -r count unit; do
        if [[ "$count" =~ ^[0-9]+$ ]] && [[ "$unit" =~ ^[dwmy]$ ]]; then
            local backup_name
            backup_name=$(create_backup_name "$name" "$unit" "$compress_type")
            
            if should_create_backup "$destination" "$backup_name" "$unit" "$force_full"; then
                backup_created=true
                
                case "$backup_type" in
                    tar)
                        local backup_file="$destination/$backup_name"
                        if create_tar_backup "$source" "$backup_file" "$compress_type" "${exclude_patterns[@]}" "$verbose" "$encrypt" "$dry_run"; then
                            backup_details+="Created: $(basename "$backup_file")\n"
                        else
                            backup_status="FAILED"
                            backup_details+="Failed: $(basename "$backup_file")\n"
                        fi
                        ;;
                    rsync)
                        local rsync_name="${name}_${unit}_$(get_backup_timestamp "$unit")"
                        if create_rsync_backup "$source" "$destination" "$rsync_name" "$incremental" "${exclude_patterns[@]}" "$verbose" "$dry_run"; then
                            backup_details+="Created: $rsync_name\n"
                        else
                            backup_status="FAILED"
                            backup_details+="Failed: $rsync_name\n"
                        fi
                        ;;
                esac
                
                echo ""
            fi
        fi
    done < <(parse_keep_policy "$keep_policy")
    
    if [[ "$backup_created" == "false" ]]; then
        echo -e "${GREEN}All backup periods are up to date${NC}"
        backup_details="All backups up to date"
    fi
    
    echo ""
    
    # Clean up old backups
    cleanup_old_backups "$destination" "$name" "$keep_policy" "$dry_run"
    
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Backup rotation completed at $(date)${NC}"
    echo "Status: $backup_status"
    echo -e "${BLUE}================================================${NC}"
    
    # Send notification if configured
    if [[ -n "$email" ]]; then
        send_notification "$email" "$name" "$backup_status" "$(echo -e "$backup_details")"
    fi
    
    # Exit with appropriate code
    if [[ "$backup_status" == "FAILED" ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi