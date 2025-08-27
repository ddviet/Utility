#!/bin/bash
# permission_fixer.sh
# Purpose:
#   - Fix common file and directory permission issues automatically
#   - Apply standard permission templates for different use cases
#   - Support ownership changes and special permission scenarios
#
# Features:
#   - Multiple permission templates: web, script, default, restrictive, public
#   - Custom permission specification with directory and file modes
#   - Ownership management with user and group changes
#   - Special fixes for SSH keys, git repositories, logs, and home directories
#   - Recursive processing with file type filtering
#   - Permission backup and restore functionality
#   - Comprehensive permission reporting and analysis
#   - Safe operations with dry-run mode and detailed logging
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

usage() {
    echo "Usage: $0 [OPTIONS] [PATH...]"
    echo ""
    echo "Permission Fixes:"
    echo "  -w, --web               Fix web server permissions (755/644)"
    echo "  -s, --script            Fix script permissions (executable)"
    echo "  -d, --default           Set default permissions (755 dirs, 644 files)"
    echo "  -r, --restrictive       Set restrictive permissions (700 dirs, 600 files)"
    echo "  -p, --public            Set public readable permissions (755 dirs, 644 files)"
    echo "  --custom DIR:FILE       Custom permissions (e.g., '755:644')"
    echo "  --owner-only            Remove group/other permissions"
    echo "  --group-read            Add group read permissions"
    echo "  --everyone-read         Add read permissions for everyone"
    echo ""
    echo "Ownership Fixes:"
    echo "  -o, --owner USER:GROUP  Change ownership"
    echo "  --web-owner             Set web server ownership (www-data)"
    echo "  --user-owner USER       Set user ownership (keep current group)"
    echo ""
    echo "Special Fixes:"
    echo "  --ssh                   Fix SSH key permissions"
    echo "  --git                   Fix git repository permissions"
    echo "  --log                   Fix log file permissions"
    echo "  --temp                  Fix temporary directory permissions"
    echo "  --home                  Fix home directory permissions"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -R, --recursive         Apply changes recursively"
    echo "  -v, --verbose           Show detailed output"
    echo "  -n, --dry-run           Show what would be changed"
    echo "  -f, --force             Continue on errors"
    echo "  -b, --backup            Create backup of permissions"
    echo "  --restore FILE          Restore permissions from backup"
    echo "  --report FILE           Generate permissions report"
    echo "  -t, --type TYPE         Only process files of type (file, dir, link)"
    echo "  -e, --exclude PATTERN   Exclude files matching pattern"
    echo ""
    echo "Examples:"
    echo "  $0 -w -R /var/www/html              # Fix web permissions"
    echo "  $0 --ssh ~/.ssh                     # Fix SSH permissions"
    echo "  $0 -d -v /home/user/documents       # Default permissions with verbose"
    echo "  $0 --custom '750:640' -R /secure    # Custom restrictive permissions"
    echo "  $0 --dry-run -R /project            # Preview changes"
    echo ""
    echo "EXAMPLES (run directly from GitHub):"
    echo "  # Using curl - fix SSH permissions"
    echo "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/permission_fixer.sh)\" -- --ssh ~/.ssh"
    echo ""
    echo "  # Using curl - preview web permission changes"
    echo "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/permission_fixer.sh)\" -- --dry-run -w /var/www"
    echo ""
    echo "  # Using wget - set default permissions"
    echo "  bash -c \"\$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/permission_fixer.sh)\" -- -d -R /home/user/project"
    echo ""
    echo "RECOMMENDED (download, review, then run):"
    echo "  curl -fsSL -o /tmp/permission_fixer.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/permission_fixer.sh"
    echo "  chmod +x /tmp/permission_fixer.sh"
    echo "  /tmp/permission_fixer.sh --help        # Show help"
    echo "  /tmp/permission_fixer.sh --dry-run -d . # Preview changes"
    exit 1
}

check_permissions() {
    local path="$1"
    
    if [[ ! -e "$path" ]]; then
        return 1
    fi
    
    local perms
    perms=$(stat -c%a "$path" 2>/dev/null || stat -f%A "$path" 2>/dev/null || echo "unknown")
    
    local owner
    owner=$(stat -c%U "$path" 2>/dev/null || stat -f%Su "$path" 2>/dev/null || echo "unknown")
    
    local group
    group=$(stat -c%G "$path" 2>/dev/null || stat -f%Sg "$path" 2>/dev/null || echo "unknown")
    
    echo "$perms:$owner:$group"
}

backup_permissions() {
    local path="$1"
    local backup_file="$2"
    local recursive="$3"
    
    echo -e "${CYAN}Creating permissions backup...${NC}"
    
    local find_opts=()
    if [[ "$recursive" == "false" ]]; then
        find_opts+=("-maxdepth" "1")
    fi
    
    {
        echo "# Permission backup created on $(date)"
        echo "# Path: $path"
        echo "# Format: path:permissions:owner:group:type"
        
        find "$path" "${find_opts[@]}" -print0 2>/dev/null | while IFS= read -r -d '' item; do
            if [[ -e "$item" ]]; then
                local perm_info
                perm_info=$(check_permissions "$item")
                
                local item_type="unknown"
                if [[ -f "$item" ]]; then
                    item_type="file"
                elif [[ -d "$item" ]]; then
                    item_type="dir"
                elif [[ -L "$item" ]]; then
                    item_type="link"
                fi
                
                echo "$item:$perm_info:$item_type"
            fi
        done
    } > "$backup_file"
    
    echo -e "${GREEN}Backup saved to: $backup_file${NC}"
}

restore_permissions() {
    local backup_file="$1"
    local dry_run="$2"
    local verbose="$3"
    
    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}Backup file not found: $backup_file${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Restoring permissions from: $backup_file${NC}"
    echo ""
    
    local restored_count=0
    local failed_count=0
    
    while IFS=':' read -r path perms owner group item_type; do
        # Skip comments and empty lines
        if [[ "$path" =~ ^#.* ]] || [[ -z "$path" ]]; then
            continue
        fi
        
        if [[ ! -e "$path" ]]; then
            if [[ "$verbose" == "true" ]]; then
                echo -e "${YELLOW}File not found: $path${NC}"
            fi
            ((failed_count++))
            continue
        fi
        
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${CYAN}Would restore: $path ($perms $owner:$group)${NC}"
            ((restored_count++))
            continue
        fi
        
        local success=true
        
        # Restore permissions
        if ! chmod "$perms" "$path" 2>/dev/null; then
            success=false
        fi
        
        # Restore ownership (if running as root or using sudo)
        if [[ $EUID -eq 0 ]] && ! chown "$owner:$group" "$path" 2>/dev/null; then
            success=false
        fi
        
        if [[ "$success" == "true" ]]; then
            if [[ "$verbose" == "true" ]]; then
                echo -e "${GREEN}Restored: $path ($perms $owner:$group)${NC}"
            fi
            ((restored_count++))
        else
            echo -e "${RED}Failed to restore: $path${NC}"
            ((failed_count++))
        fi
    done < "$backup_file"
    
    echo ""
    echo "Restored: $restored_count"
    if [[ $failed_count -gt 0 ]]; then
        echo "Failed: $failed_count"
    fi
}

generate_report() {
    local path="$1"
    local report_file="$2"
    local recursive="$3"
    
    echo -e "${CYAN}Generating permissions report...${NC}"
    
    local find_opts=()
    if [[ "$recursive" == "false" ]]; then
        find_opts+=("-maxdepth" "1")
    fi
    
    {
        echo "Permission Report"
        echo "================"
        echo "Generated: $(date)"
        echo "Path: $path"
        echo ""
        printf "%-60s %-10s %-15s %-15s %-8s\n" "Path" "Perms" "Owner" "Group" "Type"
        printf "%-60s %-10s %-15s %-15s %-8s\n" "----" "-----" "-----" "-----" "----"
        
        find "$path" "${find_opts[@]}" -print0 2>/dev/null | sort -z | while IFS= read -r -d '' item; do
            if [[ -e "$item" ]]; then
                local perm_info
                perm_info=$(check_permissions "$item")
                IFS=':' read -r perms owner group <<< "$perm_info"
                
                local item_type="?"
                if [[ -f "$item" ]]; then
                    item_type="file"
                elif [[ -d "$item" ]]; then
                    item_type="dir"
                elif [[ -L "$item" ]]; then
                    item_type="link"
                fi
                
                local display_path="$item"
                if [[ ${#display_path} -gt 58 ]]; then
                    display_path="...${display_path: -55}"
                fi
                
                printf "%-60s %-10s %-15s %-15s %-8s\n" "$display_path" "$perms" "$owner" "$group" "$item_type"
            fi
        done
        
        echo ""
        echo "Summary"
        echo "======="
        echo "Files with unusual permissions:"
        
        find "$path" "${find_opts[@]}" -type f 2>/dev/null | while read -r file; do
            local perms
            perms=$(stat -c%a "$file" 2>/dev/null || stat -f%A "$file" 2>/dev/null || echo "000")
            if [[ "$perms" =~ [13579]$ ]] || [[ "${perms:0:1}" == "7" ]]; then
                echo "  $file ($perms)"
            fi
        done
        
        echo ""
        echo "Directories with unusual permissions:"
        find "$path" "${find_opts[@]}" -type d 2>/dev/null | while read -r dir; do
            local perms
            perms=$(stat -c%a "$dir" 2>/dev/null || stat -f%A "$dir" 2>/dev/null || echo "000")
            if [[ ! "$perms" =~ ^[75] ]]; then
                echo "  $dir ($perms)"
            fi
        done
        
    } > "$report_file"
    
    echo -e "${GREEN}Report saved to: $report_file${NC}"
}

fix_permissions() {
    local path="$1"
    local fix_type="$2"
    local dir_perms="$3"
    local file_perms="$4"
    local owner="$5"
    local recursive="$6"
    local dry_run="$7"
    local verbose="$8"
    local force="$9"
    local item_type_filter="${10}"
    local exclude_pattern="${11}"
    
    local find_opts=()
    if [[ "$recursive" == "false" ]]; then
        find_opts+=("-maxdepth" "1")
    fi
    
    local success_count=0
    local error_count=0
    
    find "$path" "${find_opts[@]}" -print0 2>/dev/null | while IFS= read -r -d '' item; do
        # Skip if item doesn't exist
        if [[ ! -e "$item" ]]; then
            continue
        fi
        
        # Check exclude pattern
        if [[ -n "$exclude_pattern" ]] && echo "$item" | grep -qE "$exclude_pattern"; then
            if [[ "$verbose" == "true" ]]; then
                echo -e "${YELLOW}Excluded: $item${NC}"
            fi
            continue
        fi
        
        # Determine item type and target permissions
        local target_perms=""
        local current_type=""
        
        if [[ -f "$item" ]]; then
            current_type="file"
            target_perms="$file_perms"
        elif [[ -d "$item" ]]; then
            current_type="dir"
            target_perms="$dir_perms"
        elif [[ -L "$item" ]]; then
            current_type="link"
            # Skip symlinks for permission changes
            continue
        else
            current_type="other"
            continue
        fi
        
        # Filter by type if specified
        if [[ -n "$item_type_filter" && "$current_type" != "$item_type_filter" ]]; then
            continue
        fi
        
        # Get current permissions
        local current_perms
        current_perms=$(stat -c%a "$item" 2>/dev/null || stat -f%A "$item" 2>/dev/null || echo "000")
        
        local needs_change=false
        
        # Check if permissions need changing
        if [[ -n "$target_perms" && "$current_perms" != "$target_perms" ]]; then
            needs_change=true
        fi
        
        # Apply special fixes
        case "$fix_type" in
            ssh)
                if [[ "$(basename "$item")" == "authorized_keys" ]]; then
                    target_perms="600"
                    needs_change=true
                elif [[ "$item" =~ \.pub$ ]]; then
                    target_perms="644"
                    needs_change=true
                elif [[ "$current_type" == "file" && ! "$item" =~ \.pub$ ]]; then
                    target_perms="600"
                    needs_change=true
                elif [[ "$current_type" == "dir" ]]; then
                    target_perms="700"
                    needs_change=true
                fi
                ;;
            script)
                if [[ "$current_type" == "file" ]]; then
                    # Check if file has extension suggesting it's a script
                    if [[ "$item" =~ \.(sh|py|pl|rb|js)$ ]] || [[ -x "$item" ]]; then
                        if [[ ! "$current_perms" =~ [13579]$ ]]; then
                            target_perms="755"
                            needs_change=true
                        fi
                    fi
                fi
                ;;
            git)
                if [[ "$item" =~ \.git/hooks/ ]]; then
                    if [[ "$current_type" == "file" ]]; then
                        target_perms="755"
                        needs_change=true
                    fi
                elif [[ "$item" =~ \.git/ ]]; then
                    if [[ "$current_type" == "file" ]]; then
                        target_perms="644"
                        needs_change=true
                    elif [[ "$current_type" == "dir" ]]; then
                        target_perms="755"
                        needs_change=true
                    fi
                fi
                ;;
        esac
        
        # Show what would be changed
        if [[ "$needs_change" == "true" ]]; then
            local display_path="$item"
            if [[ ${#display_path} -gt 50 ]]; then
                display_path="...${display_path: -47}"
            fi
            
            if [[ "$dry_run" == "true" ]]; then
                echo -e "${CYAN}Would change: $display_path ($current_perms -> $target_perms)${NC}"
                ((success_count++))
            else
                # Apply permission changes
                if chmod "$target_perms" "$item" 2>/dev/null; then
                    if [[ "$verbose" == "true" ]]; then
                        echo -e "${GREEN}Changed: $display_path ($current_perms -> $target_perms)${NC}"
                    fi
                    ((success_count++))
                else
                    echo -e "${RED}Failed to change: $display_path${NC}"
                    ((error_count++))
                    if [[ "$force" == "false" ]]; then
                        break
                    fi
                fi
                
                # Apply ownership changes if specified
                if [[ -n "$owner" ]]; then
                    if [[ $EUID -eq 0 ]] || [[ "$(id -u)" == "0" ]]; then
                        if chown "$owner" "$item" 2>/dev/null; then
                            if [[ "$verbose" == "true" ]]; then
                                echo -e "${GREEN}Owner changed: $display_path -> $owner${NC}"
                            fi
                        else
                            echo -e "${YELLOW}Failed to change owner: $display_path${NC}"
                        fi
                    else
                        if [[ "$verbose" == "true" ]]; then
                            echo -e "${YELLOW}Cannot change owner (not root): $display_path${NC}"
                        fi
                    fi
                fi
            fi
        elif [[ "$verbose" == "true" ]]; then
            echo -e "${GREEN}OK: $(basename "$item") ($current_perms)${NC}"
        fi
    done
    
    echo ""
    echo "Changes applied: $success_count"
    if [[ $error_count -gt 0 ]]; then
        echo "Errors: $error_count"
    fi
}

main() {
    local paths=()
    local fix_type="default"
    local dir_perms="755"
    local file_perms="644"
    local owner=""
    local recursive=false
    local verbose=false
    local dry_run=false
    local force=false
    local backup=false
    local restore_file=""
    local report_file=""
    local item_type_filter=""
    local exclude_pattern=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -w|--web)
                fix_type="web"
                dir_perms="755"
                file_perms="644"
                shift
                ;;
            -s|--script)
                fix_type="script"
                shift
                ;;
            -d|--default)
                fix_type="default"
                dir_perms="755"
                file_perms="644"
                shift
                ;;
            -r|--restrictive)
                fix_type="restrictive"
                dir_perms="700"
                file_perms="600"
                shift
                ;;
            -p|--public)
                fix_type="public"
                dir_perms="755"
                file_perms="644"
                shift
                ;;
            --custom)
                fix_type="custom"
                IFS=':' read -r dir_perms file_perms <<< "$2"
                shift 2
                ;;
            --owner-only)
                fix_type="owner-only"
                dir_perms="700"
                file_perms="600"
                shift
                ;;
            --group-read)
                fix_type="group-read"
                dir_perms="750"
                file_perms="640"
                shift
                ;;
            --everyone-read)
                fix_type="everyone-read"
                dir_perms="755"
                file_perms="644"
                shift
                ;;
            -o|--owner)
                owner="$2"
                shift 2
                ;;
            --web-owner)
                owner="www-data:www-data"
                shift
                ;;
            --user-owner)
                owner="$2:$(id -gn "$2" 2>/dev/null || echo "$(id -gn)")"
                shift 2
                ;;
            --ssh)
                fix_type="ssh"
                shift
                ;;
            --git)
                fix_type="git"
                shift
                ;;
            --log)
                fix_type="log"
                dir_perms="755"
                file_perms="644"
                owner="syslog:adm"
                shift
                ;;
            --temp)
                fix_type="temp"
                dir_perms="1777"
                file_perms="666"
                shift
                ;;
            --home)
                fix_type="home"
                dir_perms="755"
                file_perms="644"
                shift
                ;;
            -R|--recursive)
                recursive=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -b|--backup)
                backup=true
                shift
                ;;
            --restore)
                restore_file="$2"
                shift 2
                ;;
            --report)
                report_file="$2"
                shift 2
                ;;
            -t|--type)
                item_type_filter="$2"
                shift 2
                ;;
            -e|--exclude)
                exclude_pattern="$2"
                shift 2
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                usage
                ;;
            *)
                paths+=("$1")
                shift
                ;;
        esac
    done
    
    # Handle restore operation
    if [[ -n "$restore_file" ]]; then
        restore_permissions "$restore_file" "$dry_run" "$verbose"
        exit 0
    fi
    
    # Default to current directory if no paths specified
    if [[ ${#paths[@]} -eq 0 ]]; then
        paths=(".")
    fi
    
    # Validate paths
    for path in "${paths[@]}"; do
        if [[ ! -e "$path" ]]; then
            echo -e "${RED}Path does not exist: $path${NC}"
            exit 1
        fi
    done
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           PERMISSION FIXER${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Paths: ${paths[*]}"
    echo "Fix type: $fix_type"
    echo "Directory permissions: $dir_perms"
    echo "File permissions: $file_perms"
    if [[ -n "$owner" ]]; then
        echo "Owner: $owner"
    fi
    echo "Recursive: $recursive"
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE${NC}"
    fi
    if [[ -n "$exclude_pattern" ]]; then
        echo "Exclude pattern: $exclude_pattern"
    fi
    echo "Started: $(date)"
    echo ""
    
    # Process each path
    for path in "${paths[@]}"; do
        echo -e "${CYAN}Processing: $path${NC}"
        
        # Create backup if requested
        if [[ "$backup" == "true" && "$dry_run" == "false" ]]; then
            local backup_file
            backup_file="${path//\//_}_permissions_$(date +%Y%m%d_%H%M%S).bak"
            backup_permissions "$path" "$backup_file" "$recursive"
            echo ""
        fi
        
        # Generate report if requested
        if [[ -n "$report_file" ]]; then
            generate_report "$path" "$report_file" "$recursive"
            echo ""
        fi
        
        # Fix permissions
        fix_permissions "$path" "$fix_type" "$dir_perms" "$file_perms" "$owner" "$recursive" "$dry_run" "$verbose" "$force" "$item_type_filter" "$exclude_pattern"
        
        echo ""
    done
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Permission fix completed at $(date)${NC}"
    echo -e "${BLUE}================================================${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi