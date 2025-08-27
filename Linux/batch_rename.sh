#!/bin/bash
# batch_rename.sh
# Purpose:
#   - Perform bulk file renaming operations using various patterns and rules
#   - Support regex patterns, case conversion, and custom transformations
#   - Provide safe rename operations with undo capabilities
#
# Features:
#   - Multiple rename operations: pattern replacement, case conversion, numbering
#   - Regular expression support for complex pattern matching
#   - Recursive directory processing with file type filtering
#   - Safe operations with dry-run mode and backup creation
#   - Undo functionality with operation logging
#   - Interactive mode for confirmation of each rename
#   - Custom prefix/suffix addition and extension changes
#   - Space replacement and character removal options
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
    echo "Usage: $0 [OPTIONS] [FILES...]"
    echo ""
    echo "Rename Operations:"
    echo "  -p, --pattern 'FROM:TO'  Replace pattern (supports regex)"
    echo "  -l, --lowercase          Convert to lowercase"
    echo "  -u, --uppercase          Convert to uppercase"
    echo "  -c, --capitalize         Capitalize first letter of each word"
    echo "  -s, --spaces CHAR        Replace spaces with character (e.g., '_', '-')"
    echo "  -r, --remove CHARS       Remove specific characters"
    echo "  -n, --number START       Add numbers (starting from START)"
    echo "  --prefix PREFIX          Add prefix to filenames"
    echo "  --suffix SUFFIX          Add suffix to filenames (before extension)"
    echo "  --ext EXTENSION          Change file extension"
    echo ""
    echo "Options:"
    echo "  -h, --help               Show this help message"
    echo "  -d, --directory DIR      Target directory (default: current)"
    echo "  -f, --filter PATTERN     Only rename files matching pattern"
    echo "  -e, --exclude PATTERN    Exclude files matching pattern"
    echo "  -R, --recursive          Process directories recursively"
    echo "  -t, --type TYPE          File type filter (e.g., 'jpg,png,txt')"
    echo "  -v, --verbose            Show detailed operations"
    echo "  -n, --dry-run            Show what would be renamed without renaming"
    echo "  -i, --interactive        Ask before each rename"
    echo "  -b, --backup             Create backup before renaming"
    echo "  --undo FILE              Undo previous rename using backup file"
    echo "  --save-log FILE          Save rename log for undo operations"
    echo ""
    echo "Pattern Examples:"
    echo "  -p 'IMG_:Photo_'         # Replace 'IMG_' with 'Photo_'"
    echo "  -p '([0-9]+):\\1_processed'  # Add '_processed' after numbers"
    echo "  -p '(.*)\\.(.*):\\1_backup.\\2'  # Add '_backup' before extension"
    echo ""
    echo "Examples:"
    echo "  $0 -l -s '_' *.txt                      # Lowercase and replace spaces"
    echo "  $0 -p 'IMG_:Photo_' -n 1 /photos/*.jpg  # Rename with pattern and numbers"
    echo "  $0 --prefix 'vacation_' -R /photos      # Add prefix recursively"
    echo "  $0 --dry-run -c *.docx                  # Preview capitalize operation"
    echo "  $0 --undo rename_log.txt                # Undo previous operation"
    echo ""
    echo "EXAMPLES (run directly from GitHub):"
    echo "  # Using curl - preview lowercase conversion"
    echo "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/batch_rename.sh)\" -- --dry-run -l *.txt"
    echo ""
    echo "  # Using curl - add prefix to all images"
    echo "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/batch_rename.sh)\" -- --prefix 'IMG_' *.jpg *.png"
    echo ""
    echo "  # Using wget - replace pattern in filenames"
    echo "  bash -c \"\$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/batch_rename.sh)\" -- -p 'old:new' *"
    echo ""
    echo "RECOMMENDED (download, review, then run):"
    echo "  curl -fsSL -o /tmp/batch_rename.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/batch_rename.sh"
    echo "  chmod +x /tmp/batch_rename.sh"
    echo "  /tmp/batch_rename.sh --help             # Show help"
    echo "  /tmp/batch_rename.sh --dry-run -l *.txt # Test first"
    exit 1
}

create_backup_name() {
    local original="$1"
    local counter=1
    local backup_name="${original}.bak"
    
    while [[ -e "$backup_name" ]]; do
        backup_name="${original}.bak.${counter}"
        ((counter++))
    done
    
    echo "$backup_name"
}

log_rename_operation() {
    local log_file="$1"
    local old_name="$2"
    local new_name="$3"
    local operation="$4"
    
    if [[ -n "$log_file" ]]; then
        echo "$(date -Iseconds):$operation:$old_name:$new_name" >> "$log_file"
    fi
}

apply_pattern_replacement() {
    local filename="$1"
    local pattern="$2"
    
    if [[ "$pattern" == *":"* ]]; then
        local from_pattern="${pattern%%:*}"
        local to_pattern="${pattern#*:}"
        
        # Handle regex patterns
        if command -v sed >/dev/null 2>&1; then
            echo "$filename" | sed -E "s|$from_pattern|$to_pattern|g"
        else
            # Simple string replacement fallback
            echo "${filename//$from_pattern/$to_pattern}"
        fi
    else
        echo "$filename"
    fi
}

apply_case_transformation() {
    local filename="$1"
    local transformation="$2"
    
    case "$transformation" in
        lowercase)
            echo "${filename,,}"
            ;;
        uppercase)
            echo "${filename^^}"
            ;;
        capitalize)
            # Capitalize first letter of each word
            echo "$filename" | sed 's/\b\w/\U&/g'
            ;;
        *)
            echo "$filename"
            ;;
    esac
}

apply_character_operations() {
    local filename="$1"
    local operation="$2"
    local chars="$3"
    
    case "$operation" in
        replace_spaces)
            echo "${filename// /$chars}"
            ;;
        remove_chars)
            local result="$filename"
            local i
            for ((i=0; i<${#chars}; i++)); do
                local char="${chars:$i:1}"
                result="${result//$char/}"
            done
            echo "$result"
            ;;
        *)
            echo "$filename"
            ;;
    esac
}

add_numbering() {
    local filename="$1"
    local number="$2"
    local padding="$3"
    
    local name_part="${filename%.*}"
    local ext_part=""
    
    if [[ "$filename" == *.* ]]; then
        ext_part=".${filename##*.}"
    fi
    
    printf "%s_%0*d%s" "$name_part" "$padding" "$number" "$ext_part"
}

modify_filename() {
    local filepath="$1"
    local operations=("${@:2}")
    
    local directory
    directory="$(dirname "$filepath")"
    local filename
    filename="$(basename "$filepath")"
    local name_part="${filename%.*}"
    local ext_part=""
    
    if [[ "$filename" == *.* ]]; then
        ext_part=".${filename##*.}"
    fi
    
    local new_filename="$filename"
    
    for operation in "${operations[@]}"; do
        case "$operation" in
            pattern:*)
                local pattern="${operation#pattern:}"
                new_filename=$(apply_pattern_replacement "$new_filename" "$pattern")
                ;;
            case:*)
                local transformation="${operation#case:}"
                new_filename=$(apply_case_transformation "$new_filename" "$transformation")
                ;;
            spaces:*)
                local char="${operation#spaces:}"
                new_filename=$(apply_character_operations "$new_filename" "replace_spaces" "$char")
                ;;
            remove:*)
                local chars="${operation#remove:}"
                new_filename=$(apply_character_operations "$new_filename" "remove_chars" "$chars")
                ;;
            number:*)
                local number_info="${operation#number:}"
                IFS=':' read -r start_num padding <<< "$number_info"
                new_filename=$(add_numbering "$new_filename" "$start_num" "$padding")
                ;;
            prefix:*)
                local prefix="${operation#prefix:}"
                new_filename="${prefix}${new_filename}"
                ;;
            suffix:*)
                local suffix="${operation#suffix:}"
                local new_name_part="${new_filename%.*}"
                local new_ext_part=""
                if [[ "$new_filename" == *.* ]]; then
                    new_ext_part=".${new_filename##*.}"
                fi
                new_filename="${new_name_part}${suffix}${new_ext_part}"
                ;;
            ext:*)
                local new_ext="${operation#ext:}"
                # Remove leading dot if present
                new_ext="${new_ext#.}"
                local new_name_part="${new_filename%.*}"
                new_filename="${new_name_part}.${new_ext}"
                ;;
        esac
    done
    
    echo "$directory/$new_filename"
}

should_process_file() {
    local file="$1"
    local filter_pattern="$2"
    local exclude_pattern="$3"
    local file_types="$4"
    
    # Check if file exists
    if [[ ! -e "$file" ]]; then
        return 1
    fi
    
    local filename
    filename="$(basename "$file")"
    
    # Check exclude pattern
    if [[ -n "$exclude_pattern" ]] && echo "$filename" | grep -qE "$exclude_pattern"; then
        return 1
    fi
    
    # Check filter pattern
    if [[ -n "$filter_pattern" ]] && ! echo "$filename" | grep -qE "$filter_pattern"; then
        return 1
    fi
    
    # Check file types
    if [[ -n "$file_types" ]]; then
        local ext
        ext=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')
        if [[ ",$file_types," != *",$ext,"* ]]; then
            return 1
        fi
    fi
    
    return 0
}

collect_files() {
    local directory="$1"
    local recursive="$2"
    local filter_pattern="$3"
    local exclude_pattern="$4"
    local file_types="$5"
    local explicit_files=("${@:6}")
    
    local files=()
    
    # If explicit files are provided, use those
    if [[ ${#explicit_files[@]} -gt 0 ]]; then
        for file in "${explicit_files[@]}"; do
            if should_process_file "$file" "$filter_pattern" "$exclude_pattern" "$file_types"; then
                files+=("$file")
            fi
        done
    else
        # Collect files from directory
        if [[ "$recursive" == "true" ]]; then
            while IFS= read -r -d '' file; do
                if should_process_file "$file" "$filter_pattern" "$exclude_pattern" "$file_types"; then
                    files+=("$file")
                fi
            done < <(find "$directory" -type f -print0 2>/dev/null)
        else
            for file in "$directory"/*; do
                if [[ -f "$file" ]] && should_process_file "$file" "$filter_pattern" "$exclude_pattern" "$file_types"; then
                    files+=("$file")
                fi
            done
        fi
    fi
    
    printf '%s\n' "${files[@]}" | sort
}

perform_rename() {
    local old_path="$1"
    local new_path="$2"
    local dry_run="$3"
    local interactive="$4"
    local verbose="$5"
    local backup="$6"
    local log_file="$7"
    
    if [[ "$old_path" == "$new_path" ]]; then
        if [[ "$verbose" == "true" ]]; then
            echo -e "${YELLOW}No change: $(basename "$old_path")${NC}"
        fi
        return 0
    fi
    
    if [[ -e "$new_path" ]]; then
        echo -e "${RED}Error: Target already exists: $(basename "$new_path")${NC}"
        return 1
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${CYAN}$(basename "$old_path")${NC} -> ${GREEN}$(basename "$new_path")${NC} ${YELLOW}[DRY RUN]${NC}"
        return 0
    fi
    
    if [[ "$interactive" == "true" ]]; then
        echo -e "${CYAN}$(basename "$old_path")${NC} -> ${GREEN}$(basename "$new_path")${NC}"
        read -p "Proceed with rename? (y/N): " -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Skipped"
            return 0
        fi
    fi
    
    # Create backup if requested
    if [[ "$backup" == "true" ]]; then
        local backup_name
        backup_name=$(create_backup_name "$old_path")
        if cp "$old_path" "$backup_name" 2>/dev/null; then
            if [[ "$verbose" == "true" ]]; then
                echo -e "${BLUE}Backup created: $(basename "$backup_name")${NC}"
            fi
        else
            echo -e "${YELLOW}Warning: Could not create backup${NC}"
        fi
    fi
    
    # Perform the rename
    if mv "$old_path" "$new_path" 2>/dev/null; then
        echo -e "${CYAN}$(basename "$old_path")${NC} -> ${GREEN}$(basename "$new_path")${NC}"
        log_rename_operation "$log_file" "$old_path" "$new_path" "rename"
        return 0
    else
        echo -e "${RED}Error renaming: $(basename "$old_path")${NC}"
        return 1
    fi
}

undo_renames() {
    local log_file="$1"
    local dry_run="$2"
    
    if [[ ! -f "$log_file" ]]; then
        echo -e "${RED}Log file not found: $log_file${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Undoing renames from: $log_file${NC}"
    echo ""
    
    # Read log file in reverse order
    local operations=()
    while IFS= read -r line; do
        operations=("$line" "${operations[@]}")
    done < "$log_file"
    
    local undone_count=0
    local failed_count=0
    
    for operation in "${operations[@]}"; do
        if [[ "$operation" =~ ^[^:]*:rename:(.*):(.*) ]]; then
            local old_path="${BASH_REMATCH[1]}"
            local new_path="${BASH_REMATCH[2]}"
            
            if [[ "$dry_run" == "true" ]]; then
                echo -e "${CYAN}$(basename "$new_path")${NC} -> ${GREEN}$(basename "$old_path")${NC} ${YELLOW}[DRY RUN]${NC}"
                ((undone_count++))
            else
                if [[ -e "$new_path" ]]; then
                    if mv "$new_path" "$old_path" 2>/dev/null; then
                        echo -e "${CYAN}$(basename "$new_path")${NC} -> ${GREEN}$(basename "$old_path")${NC}"
                        ((undone_count++))
                    else
                        echo -e "${RED}Failed to undo: $(basename "$new_path")${NC}"
                        ((failed_count++))
                    fi
                else
                    echo -e "${YELLOW}File not found: $(basename "$new_path")${NC}"
                    ((failed_count++))
                fi
            fi
        fi
    done
    
    echo ""
    echo "Operations undone: $undone_count"
    if [[ $failed_count -gt 0 ]]; then
        echo "Failed operations: $failed_count"
    fi
    
    if [[ "$dry_run" == "false" && $failed_count -eq 0 ]]; then
        # Archive the log file
        local archive_name="${log_file}.$(date +%Y%m%d_%H%M%S).done"
        mv "$log_file" "$archive_name"
        echo "Log file archived as: $archive_name"
    fi
}

main() {
    local directory="."
    local operations=()
    local filter_pattern=""
    local exclude_pattern=""
    local file_types=""
    local recursive=false
    local verbose=false
    local dry_run=false
    local interactive=false
    local backup=false
    local undo_file=""
    local log_file=""
    local files=()
    local number_counter=1
    local number_padding=3
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -p|--pattern)
                operations+=("pattern:$2")
                shift 2
                ;;
            -l|--lowercase)
                operations+=("case:lowercase")
                shift
                ;;
            -u|--uppercase)
                operations+=("case:uppercase")
                shift
                ;;
            -c|--capitalize)
                operations+=("case:capitalize")
                shift
                ;;
            -s|--spaces)
                operations+=("spaces:$2")
                shift 2
                ;;
            -r|--remove)
                operations+=("remove:$2")
                shift 2
                ;;
            -n|--number)
                number_counter="$2"
                operations+=("number:${number_counter}:${number_padding}")
                shift 2
                ;;
            --prefix)
                operations+=("prefix:$2")
                shift 2
                ;;
            --suffix)
                operations+=("suffix:$2")
                shift 2
                ;;
            --ext)
                operations+=("ext:$2")
                shift 2
                ;;
            -d|--directory)
                directory="$2"
                shift 2
                ;;
            -f|--filter)
                filter_pattern="$2"
                shift 2
                ;;
            -e|--exclude)
                exclude_pattern="$2"
                shift 2
                ;;
            -R|--recursive)
                recursive=true
                shift
                ;;
            -t|--type)
                file_types="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -b|--backup)
                backup=true
                shift
                ;;
            --undo)
                undo_file="$2"
                shift 2
                ;;
            --save-log)
                log_file="$2"
                shift 2
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                usage
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done
    
    # Handle undo operation
    if [[ -n "$undo_file" ]]; then
        undo_renames "$undo_file" "$dry_run"
        exit 0
    fi
    
    # Validate directory
    if [[ ! -d "$directory" ]]; then
        echo -e "${RED}Directory does not exist: $directory${NC}"
        exit 1
    fi
    
    # Check if any operations are specified
    if [[ ${#operations[@]} -eq 0 ]]; then
        echo -e "${RED}No rename operations specified${NC}"
        usage
    fi
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}             BATCH RENAME${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Directory: $directory"
    echo "Operations: ${operations[*]}"
    if [[ -n "$filter_pattern" ]]; then
        echo "Filter: $filter_pattern"
    fi
    if [[ -n "$exclude_pattern" ]]; then
        echo "Exclude: $exclude_pattern"
    fi
    if [[ -n "$file_types" ]]; then
        echo "File types: $file_types"
    fi
    echo "Recursive: $recursive"
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE${NC}"
    fi
    if [[ -n "$log_file" ]]; then
        echo "Log file: $log_file"
    fi
    echo "Started: $(date)"
    echo ""
    
    # Collect files to process
    local all_files=()
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            all_files+=("$file")
        fi
    done < <(collect_files "$directory" "$recursive" "$filter_pattern" "$exclude_pattern" "$file_types" "${files[@]}")
    
    if [[ ${#all_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No files found matching criteria${NC}"
        exit 0
    fi
    
    echo -e "${CYAN}Found ${#all_files[@]} files to process${NC}"
    echo ""
    
    # Process files
    local success_count=0
    local error_count=0
    local current_number=$number_counter
    
    for file in "${all_files[@]}"; do
        # Update number operation with current counter
        local updated_operations=()
        for op in "${operations[@]}"; do
            if [[ "$op" == number:* ]]; then
                updated_operations+=("number:${current_number}:${number_padding}")
                ((current_number++))
            else
                updated_operations+=("$op")
            fi
        done
        
        local new_path
        new_path=$(modify_filename "$file" "${updated_operations[@]}")
        
        if perform_rename "$file" "$new_path" "$dry_run" "$interactive" "$verbose" "$backup" "$log_file"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done
    
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Batch rename completed${NC}"
    echo "Files processed: ${#all_files[@]}"
    echo "Successful renames: $success_count"
    if [[ $error_count -gt 0 ]]; then
        echo "Errors: $error_count"
    fi
    if [[ -n "$log_file" && "$dry_run" == "false" ]]; then
        echo "Log saved to: $log_file"
        echo "Use --undo $log_file to reverse these changes"
    fi
    echo -e "${BLUE}================================================${NC}"
    
    # Exit with error code if there were errors
    if [[ $error_count -gt 0 ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi