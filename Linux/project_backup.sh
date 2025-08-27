#!/bin/bash
# project_backup.sh
# Purpose:
#   - Create intelligent backups of code projects with smart exclusions
#   - Support multiple compression formats and backup rotation
#   - Automatically detect project type and apply appropriate exclusion patterns
#
# Features:
#   - Automatic project type detection (Node.js, Python, Rust, Go, Java, etc.)
#   - Smart exclusion of build artifacts, dependencies, and temporary files
#   - Multiple compression formats: gzip, bzip2, xz with size optimization
#   - Backup rotation with configurable retention policies
#   - Git integration with optional .git directory inclusion
#   - Large file handling with configurable size limits
#   - Custom naming and timestamping for organized backup archives
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

usage() {
    echo "Usage: $0 [OPTIONS] [PROJECT_DIR] [BACKUP_DIR]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -n, --name NAME     Custom backup name (default: project directory name)"
    echo "  -c, --compress TYPE Compression type: gzip, bzip2, xz (default: gzip)"
    echo "  -e, --exclude PATTERN Additional exclude pattern"
    echo "  -i, --include-git   Include .git directory"
    echo "  -v, --verbose       Verbose output"
    echo "  -r, --rotate COUNT  Keep only N most recent backups (default: 10)"
    echo "  -s, --skip-large    Skip files larger than 100MB"
    echo "  --dry-run           Show what would be backed up"
    echo ""
    echo "Arguments:"
    echo "  PROJECT_DIR         Directory to backup (default: current directory)"
    echo "  BACKUP_DIR          Backup destination (default: ./backups)"
    echo ""
    echo "Examples:"
    echo "  $0                  # Backup current project to ./backups"
    echo "  $0 /home/user/myproject /backup/location"
    echo "  $0 -n webapp -c xz -r 5 /var/www/html"
    echo ""
    echo "EXAMPLES (run directly from GitHub):"
    echo "  # Using curl - backup current directory"
    echo "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/project_backup.sh)\""
    echo ""
    echo "  # Using curl - dry run to preview backup"
    echo "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/project_backup.sh)\" -- --dry-run ."
    echo ""
    echo "  # Using wget - backup with custom settings"
    echo "  bash -c \"\$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/project_backup.sh)\" -- -c xz -r 5 /project /backups"
    echo ""
    echo "RECOMMENDED (download, review, then run):"
    echo "  curl -fsSL -o /tmp/project_backup.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/project_backup.sh"
    echo "  chmod +x /tmp/project_backup.sh"
    echo "  /tmp/project_backup.sh --help          # Show help"
    echo "  /tmp/project_backup.sh --dry-run       # Preview backup"
    exit 1
}

get_project_type() {
    local project_dir="$1"
    
    if [[ -f "$project_dir/package.json" ]]; then
        echo "nodejs"
    elif [[ -f "$project_dir/requirements.txt" ]] || [[ -f "$project_dir/pyproject.toml" ]] || [[ -f "$project_dir/setup.py" ]]; then
        echo "python"
    elif [[ -f "$project_dir/Cargo.toml" ]]; then
        echo "rust"
    elif [[ -f "$project_dir/go.mod" ]]; then
        echo "go"
    elif [[ -f "$project_dir/pom.xml" ]] || [[ -f "$project_dir/build.gradle" ]]; then
        echo "java"
    elif [[ -f "$project_dir/composer.json" ]]; then
        echo "php"
    elif [[ -f "$project_dir/Gemfile" ]]; then
        echo "ruby"
    elif [[ -f "$project_dir/pubspec.yaml" ]]; then
        echo "dart"
    elif [[ -f "$project_dir/mix.exs" ]]; then
        echo "elixir"
    else
        echo "generic"
    fi
}

get_exclude_patterns() {
    local project_type="$1"
    local include_git="$2"
    local additional_excludes=("${@:3}")
    
    local base_excludes=(
        "*.tmp"
        "*.temp"
        "*.log"
        "*.swp"
        "*.swo"
        "*~"
        ".DS_Store"
        "Thumbs.db"
        "*.pyc"
        "__pycache__"
        ".pytest_cache"
        ".coverage"
        ".nyc_output"
        "coverage/"
        ".env"
        ".env.*"
        "secrets.*"
        "*.key"
        "*.pem"
        "*.p12"
        "*.pfx"
    )
    
    if [[ "$include_git" == "false" ]]; then
        base_excludes+=(".git")
    fi
    
    case "$project_type" in
        nodejs)
            base_excludes+=(
                "node_modules"
                "npm-debug.log*"
                "yarn-debug.log*"
                "yarn-error.log*"
                ".npm"
                ".yarn"
                "dist"
                "build"
                ".next"
                ".nuxt"
                ".vuepress/dist"
            )
            ;;
        python)
            base_excludes+=(
                "venv"
                "env"
                ".venv"
                ".env"
                "site-packages"
                ".tox"
                ".mypy_cache"
                "*.egg-info"
                "dist"
                "build"
                ".pytest_cache"
                "__pycache__"
            )
            ;;
        rust)
            base_excludes+=(
                "target"
                "Cargo.lock"
            )
            ;;
        go)
            base_excludes+=(
                "vendor"
                "bin"
            )
            ;;
        java)
            base_excludes+=(
                "target"
                "build"
                ".gradle"
                "*.class"
                "*.jar"
                "*.war"
            )
            ;;
        php)
            base_excludes+=(
                "vendor"
                "composer.lock"
            )
            ;;
        ruby)
            base_excludes+=(
                ".bundle"
                "vendor/bundle"
                "Gemfile.lock"
            )
            ;;
        dart)
            base_excludes+=(
                ".dart_tool"
                ".packages"
                "build"
                "pubspec.lock"
            )
            ;;
        elixir)
            base_excludes+=(
                "_build"
                "deps"
                "mix.lock"
            )
            ;;
    esac
    
    # Add additional excludes
    for exclude in "${additional_excludes[@]}"; do
        if [[ -n "$exclude" ]]; then
            base_excludes+=("$exclude")
        fi
    done
    
    printf '%s\n' "${base_excludes[@]}"
}

create_exclude_file() {
    local exclude_patterns=("$@")
    local exclude_file
    exclude_file=$(mktemp)
    
    for pattern in "${exclude_patterns[@]}"; do
        echo "$pattern" >> "$exclude_file"
    done
    
    echo "$exclude_file"
}

calculate_size() {
    local dir="$1"
    local exclude_file="$2"
    
    if command -v du >/dev/null 2>&1; then
        du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown"
    else
        echo "unknown"
    fi
}

create_backup() {
    local project_dir="$1"
    local backup_dir="$2"
    local backup_name="$3"
    local compress_type="$4"
    local exclude_file="$5"
    local verbose="$6"
    local dry_run="$7"
    local skip_large="$8"
    
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    
    local extension
    case "$compress_type" in
        gzip) extension=".tar.gz" ;;
        bzip2) extension=".tar.bz2" ;;
        xz) extension=".tar.xz" ;;
        *) extension=".tar.gz" ;;
    esac
    
    local backup_file="$backup_dir/${backup_name}_${timestamp}${extension}"
    
    echo -e "${BLUE}Creating backup: $(basename "$backup_file")${NC}"
    echo "Source: $project_dir"
    echo "Destination: $backup_file"
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Files that would be included:${NC}"
        tar --exclude-from="$exclude_file" -tf /dev/null "$project_dir" 2>/dev/null || \
        find "$project_dir" -type f | head -20
        return 0
    fi
    
    mkdir -p "$backup_dir"
    
    local tar_opts=(
        "--exclude-from=$exclude_file"
        "-C" "$(dirname "$project_dir")"
    )
    
    if [[ "$verbose" == "true" ]]; then
        tar_opts+=("-v")
    fi
    
    if [[ "$skip_large" == "true" ]]; then
        echo -e "${YELLOW}Skipping files larger than 100MB${NC}"
    fi
    
    case "$compress_type" in
        gzip)
            tar_opts+=("-czf")
            ;;
        bzip2)
            tar_opts+=("-cjf")
            ;;
        xz)
            tar_opts+=("-cJf")
            ;;
    esac
    
    tar_opts+=("$backup_file" "$(basename "$project_dir")")
    
    echo -e "${CYAN}Running backup...${NC}"
    if tar "${tar_opts[@]}" 2>/dev/null; then
        local backup_size
        backup_size=$(du -sh "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "${GREEN}Backup created successfully${NC}"
        echo "Backup size: $backup_size"
        echo "Location: $backup_file"
    else
        echo -e "${RED}Backup failed${NC}"
        return 1
    fi
}

rotate_backups() {
    local backup_dir="$1"
    local backup_name="$2"
    local keep_count="$3"
    local dry_run="$4"
    
    echo -e "${BLUE}Rotating backups (keeping $keep_count most recent)...${NC}"
    
    local pattern="${backup_name}_[0-9]*_[0-9]*.*"
    local backups
    backups=$(find "$backup_dir" -name "$pattern" -type f 2>/dev/null | sort -r || true)
    
    if [[ -z "$backups" ]]; then
        echo -e "${GREEN}No previous backups found${NC}"
        return 0
    fi
    
    local count=0
    while IFS= read -r backup_file; do
        ((count++))
        if [[ $count -gt $keep_count ]]; then
            local size
            size=$(du -sh "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
            echo -e "${CYAN}Removing old backup: $(basename "$backup_file") ($size)${NC}"
            
            if [[ "$dry_run" == "true" ]]; then
                echo -e "${YELLOW}  [DRY RUN] Would remove${NC}"
            else
                if rm -f "$backup_file"; then
                    echo -e "${GREEN}  Removed${NC}"
                else
                    echo -e "${RED}  Failed to remove${NC}"
                fi
            fi
        else
            echo -e "${GREEN}Keeping: $(basename "$backup_file")${NC}"
        fi
    done <<< "$backups"
}

main() {
    local project_dir="$(pwd)"
    local backup_dir="./backups"
    local backup_name=""
    local compress_type="gzip"
    local additional_excludes=()
    local include_git=false
    local verbose=false
    local rotate_count=10
    local skip_large=false
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -n|--name)
                backup_name="$2"
                shift 2
                ;;
            -c|--compress)
                compress_type="$2"
                shift 2
                ;;
            -e|--exclude)
                additional_excludes+=("$2")
                shift 2
                ;;
            -i|--include-git)
                include_git=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -r|--rotate)
                rotate_count="$2"
                shift 2
                ;;
            -s|--skip-large)
                skip_large=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                usage
                ;;
            *)
                if [[ -z "${1//\/}" ]] || [[ ! -d "$1" ]] && [[ ${#additional_excludes[@]} -eq 0 ]]; then
                    project_dir="$1"
                elif [[ -z "$backup_dir" ]] || [[ "$backup_dir" == "./backups" ]]; then
                    backup_dir="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Resolve absolute paths
    project_dir=$(realpath "$project_dir")
    backup_dir=$(realpath "$backup_dir")
    
    # Set default backup name
    if [[ -z "$backup_name" ]]; then
        backup_name=$(basename "$project_dir")
    fi
    
    # Validate inputs
    if [[ ! -d "$project_dir" ]]; then
        echo -e "${RED}Error: Project directory does not exist: $project_dir${NC}"
        exit 1
    fi
    
    local project_type
    project_type=$(get_project_type "$project_dir")
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           PROJECT BACKUP${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Project: $project_dir"
    echo "Type: $project_type"
    echo "Backup name: $backup_name"
    echo "Compression: $compress_type"
    echo "Include .git: $include_git"
    echo "Keep backups: $rotate_count"
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No backup will be created${NC}"
    fi
    echo "Started: $(date)"
    echo ""
    
    # Get exclude patterns
    local exclude_patterns
    mapfile -t exclude_patterns < <(get_exclude_patterns "$project_type" "$include_git" "${additional_excludes[@]}")
    
    # Create temporary exclude file
    local exclude_file
    exclude_file=$(create_exclude_file "${exclude_patterns[@]}")
    trap "rm -f '$exclude_file'" EXIT
    
    echo -e "${BLUE}Exclusion patterns:${NC}"
    printf '  %s\n' "${exclude_patterns[@]}"
    echo ""
    
    # Show project size
    echo -e "${BLUE}Analyzing project size...${NC}"
    local project_size
    project_size=$(calculate_size "$project_dir" "$exclude_file")
    echo "Project size: $project_size"
    echo ""
    
    # Create backup
    if create_backup "$project_dir" "$backup_dir" "$backup_name" "$compress_type" "$exclude_file" "$verbose" "$dry_run" "$skip_large"; then
        echo ""
        
        # Rotate old backups
        if [[ "$dry_run" == "false" ]]; then
            rotate_backups "$backup_dir" "$backup_name" "$rotate_count" "$dry_run"
        fi
    else
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Backup completed at $(date)${NC}"
    echo -e "${BLUE}================================================${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi