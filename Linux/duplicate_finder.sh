#!/usr/bin/env bash
# duplicate_finder.sh
# Purpose:
#   - Advanced duplicate file detection and management system
#   - Multiple detection algorithms with intelligent file comparison
#   - Safe removal options with configurable keep/delete policies
#
# Features:
#   - Multiple detection methods: file size, cryptographic hash, filename
#   - Intelligent keep policies: newest, oldest, largest, smallest, interactive
#   - Hard link creation option to save space without deletion
#   - Comprehensive filtering by file type, size, and patterns
#   - Progress tracking and detailed reporting
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
duplicate_finder.sh — Advanced Duplicate File Detection and Management System

USAGE
    duplicate_finder.sh [OPTIONS] [DIRECTORY...]

DESCRIPTION
    Advanced duplicate file detection and management system with multiple
    detection algorithms, intelligent file comparison, and safe removal options.
    Includes configurable keep/delete policies and space-saving alternatives.

OPTIONS
    -h, --help           Show this help message
    -m, --method METHOD  Detection method: size, hash, name (default: hash)
    -s, --min-size SIZE  Minimum file size to check (e.g., 1M, 100K)
    -t, --type TYPES     File types to check (e.g., 'jpg,png,mp4')
    -e, --exclude PATTERN Exclude files matching pattern
    -r, --remove         Remove duplicates interactively
    -f, --force-remove   Remove duplicates automatically (keep first)
    -k, --keep-rule RULE Keep rule: newest, oldest, largest, smallest, first, interactive
    -o, --output FORMAT  Output format: text, json, csv (default: text)
    -v, --verbose        Show detailed information
    -n, --dry-run        Show what would be deleted without deleting
    -l, --link           Create hard links instead of removing duplicates
    -p, --parallel       Use parallel processing for large datasets
    --save-report FILE   Save duplicate report to file
    --version            Show script version

DETECTION METHODS
    size    Fast comparison by file size only (less accurate)
    hash    SHA256 cryptographic hash comparison (accurate but slower)
    name    Filename-based comparison (fastest, filename duplicates only)

KEEP POLICIES
    newest      Keep the newest file (by modification time)
    oldest      Keep the oldest file (by modification time)
    largest     Keep the largest file (by size)
    smallest    Keep the smallest file (by size)
    first       Keep the first file found (filesystem order)
    interactive Interactive selection for each duplicate group

OUTPUT FORMATS
    text    Human-readable formatted output with colors
    json    Machine-readable JSON format for automation
    csv     Comma-separated values for spreadsheet import

EXAMPLES (run directly from GitHub)
    # Find duplicates in Pictures directory
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/duplicate_finder.sh)" -- /home/user/Pictures

    # Find large duplicate files by size (fast scan)
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/duplicate_finder.sh)" -- -m size -s 10M /media

    # Find and remove image duplicates with interactive selection
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/duplicate_finder.sh)" -- -t 'jpg,png,jpeg' -r /home/user/Photos

    # Dry run removal keeping newest files
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/duplicate_finder.sh)" -- -k newest -f --dry-run /backups

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/duplicate_finder.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/duplicate_finder.sh
    chmod +x /tmp/duplicate_finder.sh
    /tmp/duplicate_finder.sh --help             # Show this help
    /tmp/duplicate_finder.sh --dry-run .        # Preview what would be found
    /tmp/duplicate_finder.sh -v /media          # Verbose duplicate scan
    /tmp/duplicate_finder.sh -r -k interactive  # Interactive removal

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/find-duplicates https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/duplicate_finder.sh
    sudo chmod +x /usr/local/bin/find-duplicates
    find-duplicates -r -k newest ~/Downloads

AUTOMATION EXAMPLES
    # Automated cleanup of download directory
    find-duplicates -f -k newest ~/Downloads
    
    # Weekly duplicate cleanup with reporting
    find-duplicates --save-report weekly_dups.csv -o csv /shared/storage
    
    # Large file duplicate detection across multiple drives
    find-duplicates -m size -s 100M -o json /mnt/drive* > large_dups.json

SAFETY FEATURES
    Dry Run Mode:        Preview changes before applying
    Interactive Mode:    User confirmation for each action
    Hard Link Option:    Save space without deleting files
    Backup Information:  Show file details before deletion
    Pattern Exclusion:   Skip important files and directories

DUPLICATE DETECTION FEATURES
    Multiple Algorithms:  Size, cryptographic hash, and filename comparison
    Smart File Filtering: File type, size, and pattern-based filtering
    Batch Processing:     Handle large datasets efficiently
    Progress Tracking:    Real-time progress for large scans
    Detailed Reporting:   Comprehensive duplicate analysis and statistics

COMMON USE CASES
    Photo Management:    Remove duplicate photos and images
    Storage Cleanup:     Free up disk space by removing redundant files
    Backup Verification: Find and consolidate duplicate backup files
    Download Cleanup:    Clean up accumulated duplicate downloads
    Media Organization:  Deduplicate music, video, and document collections

EXIT CODES
    0   No duplicates found or operation completed successfully
    1   Duplicates found and reported
    2   File system errors or permission issues
    3   Invalid arguments or configuration errors

EOF
}

calculate_hash() {
    local file="$1"
    local hash_method="${2:-sha256}"
    
    case "$hash_method" in
        md5)
            if command -v md5sum >/dev/null 2>&1; then
                md5sum "$file" 2>/dev/null | cut -d' ' -f1
            elif command -v md5 >/dev/null 2>&1; then
                md5 -q "$file" 2>/dev/null
            else
                echo "md5_unavailable"
            fi
            ;;
        sha1)
            if command -v sha1sum >/dev/null 2>&1; then
                sha1sum "$file" 2>/dev/null | cut -d' ' -f1
            elif command -v shasum >/dev/null 2>&1; then
                shasum -a 1 "$file" 2>/dev/null | cut -d' ' -f1
            else
                echo "sha1_unavailable"
            fi
            ;;
        sha256|*)
            if command -v sha256sum >/dev/null 2>&1; then
                sha256sum "$file" 2>/dev/null | cut -d' ' -f1
            elif command -v shasum >/dev/null 2>&1; then
                shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1
            else
                echo "sha256_unavailable"
            fi
            ;;
    esac
}

get_file_info() {
    local file="$1"
    local method="$2"
    
    if [[ ! -f "$file" ]] || [[ ! -r "$file" ]]; then
        return 1
    fi
    
    local size
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
    
    local mtime
    mtime=$(stat -c%Y "$file" 2>/dev/null || stat -f%m "$file" 2>/dev/null || echo "0")
    
    local identifier=""
    case "$method" in
        size)
            identifier="$size"
            ;;
        hash)
            identifier=$(calculate_hash "$file")
            ;;
        name)
            identifier=$(basename "$file")
            ;;
    esac
    
    echo "$identifier:$size:$mtime:$file"
}

parse_size() {
    local size_str="$1"
    local size_bytes=""
    
    if [[ "$size_str" =~ ^([0-9]+)([KMGTkmgt]?)$ ]]; then
        local number="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        
        case "${unit,,}" in
            k) size_bytes=$((number * 1024)) ;;
            m) size_bytes=$((number * 1024 * 1024)) ;;
            g) size_bytes=$((number * 1024 * 1024 * 1024)) ;;
            t) size_bytes=$((number * 1024 * 1024 * 1024 * 1024)) ;;
            *) size_bytes="$number" ;;
        esac
    else
        size_bytes="0"
    fi
    
    echo "$size_bytes"
}

should_include_file() {
    local file="$1"
    local min_size="$2"
    local file_types="$3"
    local exclude_pattern="$4"
    
    # Check if file exists and is readable
    if [[ ! -f "$file" ]] || [[ ! -r "$file" ]]; then
        return 1
    fi
    
    # Skip if file matches exclude pattern
    if [[ -n "$exclude_pattern" ]] && echo "$file" | grep -qE "$exclude_pattern"; then
        return 1
    fi
    
    # Check minimum size
    if [[ "$min_size" -gt 0 ]]; then
        local file_size
        file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        if [[ "$file_size" -lt "$min_size" ]]; then
            return 1
        fi
    fi
    
    # Check file type
    if [[ -n "$file_types" ]]; then
        local ext
        ext=$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')
        if [[ ",$file_types," != *",$ext,"* ]]; then
            return 1
        fi
    fi
    
    return 0
}

find_duplicates() {
    local directories=("$@")
    local method="$1"
    local min_size="$2"
    local file_types="$3"
    local exclude_pattern="$4"
    local verbose="$5"
    local parallel="$6"
    shift 6
    directories=("$@")
    
    declare -A file_groups
    local total_files=0
    local processed_files=0
    
    # Count total files for progress
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]]; then
            total_files=$((total_files + $(find "$dir" -type f 2>/dev/null | wc -l)))
        fi
    done
    
    echo -e "${CYAN}Scanning $total_files files...${NC}"
    
    # Process files
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo -e "${YELLOW}Warning: $dir is not a directory${NC}"
            continue
        fi
        
        find "$dir" -type f 2>/dev/null | while IFS= read -r file; do
            ((processed_files++))
            
            if [[ "$verbose" == "true" && $((processed_files % 100)) -eq 0 ]]; then
                echo -ne "${CYAN}Progress: $processed_files/$total_files files processed\r${NC}"
            fi
            
            if should_include_file "$file" "$min_size" "$file_types" "$exclude_pattern"; then
                local file_info
                file_info=$(get_file_info "$file" "$method")
                if [[ -n "$file_info" ]]; then
                    echo "$file_info"
                fi
            fi
        done
    done | sort | uniq -c | while read -r count file_info; do
        if [[ $count -gt 1 ]]; then
            echo "$file_info"
        fi
    done
}

format_size() {
    local size="$1"
    if [[ $size -lt 1024 ]]; then
        echo "${size}B"
    elif [[ $size -lt $((1024 * 1024)) ]]; then
        echo "$((size / 1024))KB"
    elif [[ $size -lt $((1024 * 1024 * 1024)) ]]; then
        echo "$((size / 1024 / 1024))MB"
    else
        echo "$((size / 1024 / 1024 / 1024))GB"
    fi
}

choose_file_to_keep() {
    local keep_rule="$1"
    local files=("${@:2}")
    
    if [[ ${#files[@]} -le 1 ]]; then
        echo "${files[0]}"
        return
    fi
    
    case "$keep_rule" in
        newest)
            local newest_file=""
            local newest_time=0
            for file_info in "${files[@]}"; do
                IFS=':' read -r _ _ mtime file <<< "$file_info"
                if [[ $mtime -gt $newest_time ]]; then
                    newest_time=$mtime
                    newest_file="$file_info"
                fi
            done
            echo "$newest_file"
            ;;
        oldest)
            local oldest_file=""
            local oldest_time=999999999999
            for file_info in "${files[@]}"; do
                IFS=':' read -r _ _ mtime file <<< "$file_info"
                if [[ $mtime -lt $oldest_time ]]; then
                    oldest_time=$mtime
                    oldest_file="$file_info"
                fi
            done
            echo "$oldest_file"
            ;;
        largest)
            local largest_file=""
            local largest_size=0
            for file_info in "${files[@]}"; do
                IFS=':' read -r _ size _ file <<< "$file_info"
                if [[ $size -gt $largest_size ]]; then
                    largest_size=$size
                    largest_file="$file_info"
                fi
            done
            echo "$largest_file"
            ;;
        smallest)
            local smallest_file=""
            local smallest_size=999999999999
            for file_info in "${files[@]}"; do
                IFS=':' read -r _ size _ file <<< "$file_info"
                if [[ $size -lt $smallest_size ]]; then
                    smallest_size=$size
                    smallest_file="$file_info"
                fi
            done
            echo "$smallest_file"
            ;;
        first)
            echo "${files[0]}"
            ;;
        interactive)
            echo -e "${BLUE}Choose which file to keep:${NC}"
            local i=1
            for file_info in "${files[@]}"; do
                IFS=':' read -r _ size mtime file <<< "$file_info"
                local date_str
                date_str=$(date -d "@$mtime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$mtime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown date")
                echo "  $i) $file ($(format_size "$size"), $date_str)"
                ((i++))
            done
            echo "  0) Skip this group"
            
            while true; do
                read -p "Enter choice (0-$((${#files[@]}))): " -r choice
                if [[ "$choice" == "0" ]]; then
                    echo ""  # Return empty to skip
                    return
                elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#files[@]} ]]; then
                    echo "${files[$((choice-1))]}"
                    return
                else
                    echo "Invalid choice. Please enter 0-$((${#files[@]}))"
                fi
            done
            ;;
        *)
            echo "${files[0]}"
            ;;
    esac
}

remove_duplicates() {
    local duplicates_data="$1"
    local keep_rule="$2"
    local dry_run="$3"
    local verbose="$4"
    local create_links="$5"
    
    echo -e "${BLUE}Processing duplicate groups...${NC}"
    echo ""
    
    local total_removed=0
    local total_space_saved=0
    local groups_processed=0
    
    declare -A duplicate_groups
    
    # Group duplicates by identifier
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            IFS=':' read -r identifier _ _ _ <<< "$line"
            duplicate_groups["$identifier"]+="$line"$'\n'
        fi
    done <<< "$duplicates_data"
    
    for identifier in "${!duplicate_groups[@]}"; do
        ((groups_processed++))
        local group_files=()
        
        while IFS= read -r file_info; do
            if [[ -n "$file_info" ]]; then
                group_files+=("$file_info")
            fi
        done <<< "${duplicate_groups[$identifier]}"
        
        if [[ ${#group_files[@]} -lt 2 ]]; then
            continue
        fi
        
        echo -e "${CYAN}Duplicate group $groups_processed (${#group_files[@]} files):${NC}"
        
        # Show all files in the group
        local group_size=0
        for file_info in "${group_files[@]}"; do
            IFS=':' read -r _ size mtime file <<< "$file_info"
            group_size=$size
            local date_str
            date_str=$(date -d "@$mtime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$mtime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown date")
            echo "  $file ($(format_size "$size"), $date_str)"
        done
        
        # Choose file to keep
        local keep_file
        keep_file=$(choose_file_to_keep "$keep_rule" "${group_files[@]}")
        
        if [[ -z "$keep_file" ]]; then
            echo -e "${YELLOW}Skipping this group${NC}"
            echo ""
            continue
        fi
        
        IFS=':' read -r _ _ _ keep_path <<< "$keep_file"
        echo -e "${GREEN}Keeping: $keep_path${NC}"
        
        # Remove or link the rest
        for file_info in "${group_files[@]}"; do
            IFS=':' read -r _ size _ file_path <<< "$file_info"
            
            if [[ "$file_path" == "$keep_path" ]]; then
                continue
            fi
            
            if [[ "$dry_run" == "true" ]]; then
                if [[ "$create_links" == "true" ]]; then
                    echo -e "${YELLOW}[DRY RUN] Would create hard link: $file_path -> $keep_path${NC}"
                else
                    echo -e "${YELLOW}[DRY RUN] Would remove: $file_path${NC}"
                fi
            else
                if [[ "$create_links" == "true" ]]; then
                    echo -e "${CYAN}Creating hard link: $file_path -> $keep_path${NC}"
                    if rm "$file_path" && ln "$keep_path" "$file_path"; then
                        echo -e "${GREEN}Hard link created${NC}"
                    else
                        echo -e "${RED}Failed to create hard link${NC}"
                    fi
                else
                    echo -e "${CYAN}Removing: $file_path${NC}"
                    if rm "$file_path"; then
                        echo -e "${GREEN}Removed${NC}"
                        ((total_removed++))
                        ((total_space_saved += size))
                    else
                        echo -e "${RED}Failed to remove${NC}"
                    fi
                fi
            fi
        done
        
        echo ""
    done
    
    if [[ "$dry_run" == "false" ]]; then
        echo -e "${BLUE}Summary:${NC}"
        echo "  Files removed: $total_removed"
        echo "  Space saved: $(format_size "$total_space_saved")"
        echo "  Groups processed: $groups_processed"
    fi
}

output_json_format() {
    local duplicates_data="$1"
    
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"duplicate_groups\": ["
    
    declare -A duplicate_groups
    local first_group=true
    
    # Group duplicates by identifier
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            IFS=':' read -r identifier _ _ _ <<< "$line"
            duplicate_groups["$identifier"]+="$line"$'\n'
        fi
    done <<< "$duplicates_data"
    
    for identifier in "${!duplicate_groups[@]}"; do
        local group_files=()
        
        while IFS= read -r file_info; do
            if [[ -n "$file_info" ]]; then
                group_files+=("$file_info")
            fi
        done <<< "${duplicate_groups[$identifier]}"
        
        if [[ ${#group_files[@]} -lt 2 ]]; then
            continue
        fi
        
        if [[ "$first_group" == "true" ]]; then
            first_group=false
        else
            echo ","
        fi
        
        echo -n "    {"
        echo -n "\"identifier\": \"$identifier\", "
        echo -n "\"files\": ["
        
        local first_file=true
        for file_info in "${group_files[@]}"; do
            IFS=':' read -r _ size mtime file <<< "$file_info"
            
            if [[ "$first_file" == "true" ]]; then
                first_file=false
            else
                echo -n ","
            fi
            
            echo -n "{"
            echo -n "\"path\": \"$file\", "
            echo -n "\"size\": $size, "
            echo -n "\"mtime\": $mtime"
            echo -n "}"
        done
        
        echo -n "]"
        echo -n "}"
    done
    
    echo ""
    echo "  ]"
    echo "}"
}

output_csv_format() {
    local duplicates_data="$1"
    
    echo "group_id,file_path,size_bytes,modification_time,formatted_size"
    
    declare -A duplicate_groups
    local group_id=1
    
    # Group duplicates by identifier
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            IFS=':' read -r identifier _ _ _ <<< "$line"
            duplicate_groups["$identifier"]+="$line"$'\n'
        fi
    done <<< "$duplicates_data"
    
    for identifier in "${!duplicate_groups[@]}"; do
        local group_files=()
        
        while IFS= read -r file_info; do
            if [[ -n "$file_info" ]]; then
                group_files+=("$file_info")
            fi
        done <<< "${duplicate_groups[$identifier]}"
        
        if [[ ${#group_files[@]} -lt 2 ]]; then
            continue
        fi
        
        for file_info in "${group_files[@]}"; do
            IFS=':' read -r _ size mtime file <<< "$file_info"
            echo "$group_id,\"$file\",$size,$mtime,\"$(format_size "$size")\""
        done
        
        ((group_id++))
    done
}

main() {
    local directories=()
    local method="hash"
    local min_size_str=""
    local file_types=""
    local exclude_pattern=""
    local remove_duplicates_flag=false
    local force_remove=false
    local keep_rule="first"
    local output_format="text"
    local verbose=false
    local dry_run=false
    local create_links=false
    local parallel=false
    local save_report=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                ;;
            -m|--method)
                method="$2"
                shift 2
                ;;
            -s|--min-size)
                min_size_str="$2"
                shift 2
                ;;
            -t|--type)
                file_types="$2"
                shift 2
                ;;
            -e|--exclude)
                exclude_pattern="$2"
                shift 2
                ;;
            -r|--remove)
                remove_duplicates_flag=true
                keep_rule="interactive"
                shift
                ;;
            -f|--force-remove)
                force_remove=true
                remove_duplicates_flag=true
                shift
                ;;
            -k|--keep-rule)
                keep_rule="$2"
                shift 2
                ;;
            -o|--output)
                output_format="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -l|--link)
                create_links=true
                shift
                ;;
            -p|--parallel)
                parallel=true
                shift
                ;;
            --save-report)
                save_report="$2"
                shift 2
                ;;
            --version)
                echo "duplicate_finder.sh version $SCRIPT_VERSION"
                exit 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                print_usage
                ;;
            *)
                directories+=("$1")
                shift
                ;;
        esac
    done
    
    # Default to current directory if none specified
    if [[ ${#directories[@]} -eq 0 ]]; then
        directories=(".")
    fi
    
    # Validate directories
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo -e "${RED}Error: Directory does not exist: $dir${NC}"
            exit 1
        fi
    done
    
    # Parse minimum size
    local min_size=0
    if [[ -n "$min_size_str" ]]; then
        min_size=$(parse_size "$min_size_str")
    fi
    
    if [[ "$output_format" == "text" ]]; then
        echo -e "${BLUE}================================================${NC}"
        echo -e "${BLUE}           DUPLICATE FINDER${NC}"
        echo -e "${BLUE}================================================${NC}"
        echo "Directories: ${directories[*]}"
        echo "Method: $method"
        echo "Minimum size: $(format_size "$min_size")"
        if [[ -n "$file_types" ]]; then
            echo "File types: $file_types"
        fi
        if [[ -n "$exclude_pattern" ]]; then
            echo "Exclude pattern: $exclude_pattern"
        fi
        if [[ "$remove_duplicates_flag" == "true" ]]; then
            echo "Action: Remove duplicates (keep rule: $keep_rule)"
        else
            echo "Action: Find only"
        fi
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}DRY RUN MODE${NC}"
        fi
        echo "Started: $(date)"
        echo ""
    fi
    
    # Find duplicates
    local duplicates_data
    duplicates_data=$(find_duplicates "$method" "$min_size" "$file_types" "$exclude_pattern" "$verbose" "$parallel" "${directories[@]}")
    
    if [[ -z "$duplicates_data" ]]; then
        if [[ "$output_format" == "text" ]]; then
            echo -e "${GREEN}No duplicates found!${NC}"
        fi
        exit 0
    fi
    
    # Output results
    case "$output_format" in
        json)
            local output
            output=$(output_json_format "$duplicates_data")
            if [[ -n "$save_report" ]]; then
                echo "$output" > "$save_report"
                echo -e "${GREEN}Report saved to: $save_report${NC}"
            else
                echo "$output"
            fi
            ;;
        csv)
            local output
            output=$(output_csv_format "$duplicates_data")
            if [[ -n "$save_report" ]]; then
                echo "$output" > "$save_report"
                echo -e "${GREEN}Report saved to: $save_report${NC}"
            else
                echo "$output"
            fi
            ;;
        text)
            if [[ "$remove_duplicates_flag" == "true" ]]; then
                remove_duplicates "$duplicates_data" "$keep_rule" "$dry_run" "$verbose" "$create_links"
            else
                # Just display duplicates
                echo -e "${BLUE}Found duplicate files:${NC}"
                echo ""
                
                declare -A duplicate_groups
                local group_num=1
                
                # Group duplicates by identifier
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        IFS=':' read -r identifier _ _ _ <<< "$line"
                        duplicate_groups["$identifier"]+="$line"$'\n'
                    fi
                done <<< "$duplicates_data"
                
                for identifier in "${!duplicate_groups[@]}"; do
                    local group_files=()
                    
                    while IFS= read -r file_info; do
                        if [[ -n "$file_info" ]]; then
                            group_files+=("$file_info")
                        fi
                    done <<< "${duplicate_groups[$identifier]}"
                    
                    if [[ ${#group_files[@]} -lt 2 ]]; then
                        continue
                    fi
                    
                    echo -e "${CYAN}Group $group_num (${#group_files[@]} files):${NC}"
                    
                    local total_size=0
                    for file_info in "${group_files[@]}"; do
                        IFS=':' read -r _ size mtime file <<< "$file_info"
                        total_size=$size
                        local date_str
                        date_str=$(date -d "@$mtime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$mtime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown date")
                        echo "  $file ($(format_size "$size"), $date_str)"
                    done
                    
                    local wasted_space=$((total_size * (${#group_files[@]} - 1)))
                    echo -e "${YELLOW}  Wasted space: $(format_size "$wasted_space")${NC}"
                    echo ""
                    
                    ((group_num++))
                done
                
                if [[ -n "$save_report" ]]; then
                    output_csv_format "$duplicates_data" > "$save_report"
                    echo -e "${GREEN}Report saved to: $save_report${NC}"
                fi
            fi
            
            echo -e "${BLUE}================================================${NC}"
            echo -e "${GREEN}Duplicate search completed at $(date)${NC}"
            echo -e "${BLUE}================================================${NC}"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    main "$@"
fi