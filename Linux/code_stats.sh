#!/bin/bash
# code_stats.sh
# Purpose:
#   - Generate comprehensive statistics and analysis for code projects
#   - Support multiple programming languages with detailed metrics
#   - Provide development timeline and contributor analysis
#
# Features:
#   - Multi-language code analysis with automatic detection
#   - File, line, and size statistics with detailed breakdowns
#   - Git integration for author statistics and development timeline
#   - Language-specific metrics and complexity analysis
#   - Customizable file filtering and directory depth control
#   - Multiple output formats: text, JSON, CSV for integration
#   - Project health metrics and code quality indicators
#   - Exclude pattern support for build artifacts and dependencies
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
code_stats.sh — Comprehensive Code Analysis and Statistics Tool

USAGE
    code_stats.sh [OPTIONS] [DIRECTORY]

DESCRIPTION
    Generate comprehensive statistics and analysis for code projects with
    multi-language support, detailed metrics, and development timeline analysis.
    Provides insights into project structure, code quality, and team contributions.

OPTIONS
    -h, --help           Show this help message
    -d, --detailed       Show detailed statistics per file
    -l, --languages      Show statistics by programming language
    -a, --authors        Show statistics by git authors
    -t, --timeline       Show development timeline (requires git)
    -e, --exclude PATTERN Exclude files matching pattern
    -o, --output FORMAT  Output format: text, json, csv (default: text)
    --min-size BYTES     Minimum file size to include (default: 1)
    --max-depth DEPTH    Maximum directory depth (default: unlimited)
    --version            Show script version

SUPPORTED LANGUAGES
    JavaScript, Python, Java, C/C++, C#, PHP, Ruby, Go, Rust, Swift,
    Kotlin, Scala, R, MATLAB, Shell, PowerShell, Perl, Lua, HTML, CSS,
    SQL, XML, JSON, YAML, TOML, Markdown, Docker, Makefile

OUTPUT FORMATS
    text    Human-readable formatted output with colors
    json    Machine-readable JSON format for automation
    csv     Comma-separated values for spreadsheet import

EXAMPLES (run directly from GitHub)
    # Basic code statistics for current directory
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/code_stats.sh)"

    # Language and author statistics with detailed breakdown
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/code_stats.sh)" -- -l -a -d .

    # JSON output for automation and CI/CD integration
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/code_stats.sh)" -- -o json --detailed

    # Timeline analysis for project history
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/code_stats.sh)" -- -t -a /path/to/project

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/code_stats.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/code_stats.sh
    chmod +x /tmp/code_stats.sh
    /tmp/code_stats.sh --help               # Show this help
    /tmp/code_stats.sh -l                   # Language statistics
    /tmp/code_stats.sh -a -t                # Author and timeline analysis
    /tmp/code_stats.sh -o json > stats.json # Export to JSON

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/code-stats https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/code_stats.sh
    sudo chmod +x /usr/local/bin/code-stats
    code-stats -l -a .

AUTOMATION EXAMPLES
    # CI/CD integration for code metrics
    code-stats -o json --detailed > metrics.json
    
    # Weekly project analysis report
    code-stats -l -a -t /projects/webapp | mail -s "Weekly Code Stats" team@company.com
    
    # Multi-project comparison
    for project in ~/projects/*/; do
        echo "=== $project ==="
        code-stats -l "$project"
    done

PROJECT ANALYSIS FEATURES
    Language Detection:   Automatic identification of 25+ programming languages
    Code Metrics:        Lines of code, comments, blank lines per language
    File Analysis:       Size, complexity, and distribution statistics
    Git Integration:     Author contributions and development timeline
    Quality Metrics:     Comment ratios and code organization insights

COMMON USE CASES
    Project Assessment:   Evaluate codebase size and complexity
    Team Analytics:      Analyze developer contributions and patterns
    Language Migration:  Track technology stack evolution
    Code Review:         Identify areas needing attention or refactoring
    Documentation:       Generate project statistics for reports

EXIT CODES
    0   Analysis completed successfully
    1   Directory not found or access denied
    2   Invalid output format or options
    3   Git repository errors (for git-based features)

EOF
}

declare -A LANGUAGE_EXTENSIONS=(
    ["JavaScript"]="js,jsx,ts,tsx,mjs,cjs"
    ["Python"]="py,pyx,pyi,pyw"
    ["Java"]="java"
    ["C"]="c,h"
    ["C++"]="cpp,cxx,cc,hpp,hxx,hh"
    ["C#"]="cs"
    ["PHP"]="php,phtml"
    ["Ruby"]="rb,rbw"
    ["Go"]="go"
    ["Rust"]="rs"
    ["Swift"]="swift"
    ["Kotlin"]="kt,kts"
    ["Scala"]="scala,sc"
    ["R"]="r,R"
    ["MATLAB"]="m"
    ["Shell"]="sh,bash,zsh,fish"
    ["PowerShell"]="ps1,psm1,psd1"
    ["Perl"]="pl,pm,t"
    ["Lua"]="lua"
    ["HTML"]="html,htm,xhtml"
    ["CSS"]="css,scss,sass,less"
    ["SQL"]="sql,mysql,pgsql"
    ["XML"]="xml,xsl,xsd"
    ["JSON"]="json,jsonl"
    ["YAML"]="yaml,yml"
    ["TOML"]="toml"
    ["Markdown"]="md,markdown,mdown,mkd"
    ["Docker"]="dockerfile"
    ["Makefile"]="makefile,mk"
)

declare -A LANGUAGE_COMMENTS=(
    ["JavaScript"]="//"
    ["Python"]="#"
    ["Java"]="//"
    ["C"]="//"
    ["C++"]="//"
    ["C#"]="//"
    ["PHP"]="//"
    ["Ruby"]="#"
    ["Go"]="//"
    ["Rust"]="//"
    ["Swift"]="//"
    ["Kotlin"]="//"
    ["Scala"]="//"
    ["R"]="#"
    ["MATLAB"]"%"
    ["Shell"]="#"
    ["PowerShell"]="#"
    ["Perl"]="#"
    ["Lua"]="--"
    ["SQL"]="--"
)

get_file_language() {
    local file="$1"
    local ext
    ext=$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')
    
    # Special cases
    case "$(basename "$file")" in
        [Dd]ockerfile*|dockerfile*) echo "Docker"; return ;;
        [Mm]akefile*|makefile*) echo "Makefile"; return ;;
        *.config.js|*.conf.js) echo "JavaScript"; return ;;
    esac
    
    for lang in "${!LANGUAGE_EXTENSIONS[@]}"; do
        local extensions="${LANGUAGE_EXTENSIONS[$lang]}"
        if [[ ",$extensions," == *",$ext,"* ]]; then
            echo "$lang"
            return
        fi
    done
    
    echo "Other"
}

count_lines_in_file() {
    local file="$1"
    local language="$2"
    
    if [[ ! -f "$file" ]] || [[ ! -r "$file" ]]; then
        echo "0 0 0"
        return
    fi
    
    local total_lines
    total_lines=$(wc -l < "$file" 2>/dev/null || echo "0")
    
    local blank_lines
    blank_lines=$(grep -c "^[[:space:]]*$" "$file" 2>/dev/null || echo "0")
    
    local comment_lines=0
    if [[ -n "${LANGUAGE_COMMENTS[$language]:-}" ]]; then
        local comment_char="${LANGUAGE_COMMENTS[$language]}"
        comment_lines=$(grep -c "^[[:space:]]*${comment_char}" "$file" 2>/dev/null || echo "0")
    fi
    
    local code_lines=$((total_lines - blank_lines - comment_lines))
    
    echo "$total_lines $code_lines $comment_lines"
}

analyze_directory() {
    local dir="$1"
    local exclude_pattern="$2"
    local min_size="$3"
    local max_depth="$4"
    local detailed="$5"
    
    local find_args=("$dir" "-type" "f")
    
    if [[ -n "$max_depth" ]]; then
        find_args+=("-maxdepth" "$max_depth")
    fi
    
    if [[ -n "$min_size" ]]; then
        find_args+=("-size" "+${min_size}c")
    fi
    
    if [[ -n "$exclude_pattern" ]]; then
        find_args+=("!" "-path" "*$exclude_pattern*")
    fi
    
    declare -A language_stats
    declare -A file_details
    local total_files=0
    local total_size=0
    local total_lines=0
    local total_code_lines=0
    local total_comment_lines=0
    
    while IFS= read -r -d '' file; do
        # Skip binary files
        if file "$file" 2>/dev/null | grep -q "binary"; then
            continue
        fi
        
        local size
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        
        local language
        language=$(get_file_language "$file")
        
        local line_counts
        line_counts=$(count_lines_in_file "$file" "$language")
        read -r lines code_lines comment_lines <<< "$line_counts"
        
        # Update totals
        ((total_files++))
        ((total_size += size))
        ((total_lines += lines))
        ((total_code_lines += code_lines))
        ((total_comment_lines += comment_lines))
        
        # Update language stats
        if [[ -z "${language_stats[$language]:-}" ]]; then
            language_stats[$language]="0 0 0 0 0"
        fi
        
        local lang_stats="${language_stats[$language]}"
        read -r lang_files lang_size lang_lines lang_code lang_comments <<< "$lang_stats"
        
        ((lang_files++))
        ((lang_size += size))
        ((lang_lines += lines))
        ((lang_code += code_lines))
        ((lang_comments += comment_lines))
        
        language_stats[$language]="$lang_files $lang_size $lang_lines $lang_code $lang_comments"
        
        # Store file details if needed
        if [[ "$detailed" == "true" ]]; then
            file_details["$file"]="$language $size $lines $code_lines $comment_lines"
        fi
    done < <(find "${find_args[@]}" -print0 2>/dev/null || true)
    
    # Output results
    echo "SUMMARY:$total_files:$total_size:$total_lines:$total_code_lines:$total_comment_lines"
    
    for language in "${!language_stats[@]}"; do
        echo "LANGUAGE:$language:${language_stats[$language]}"
    done
    
    if [[ "$detailed" == "true" ]]; then
        for file in "${!file_details[@]}"; do
            echo "FILE:$file:${file_details[$file]}"
        done
    fi
}

get_git_stats() {
    local dir="$1"
    
    if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi
    
    echo -e "${BLUE}Git Repository Statistics:${NC}"
    
    # Basic git info
    local total_commits
    total_commits=$(git -C "$dir" rev-list --all --count 2>/dev/null || echo "0")
    
    local branches
    branches=$(git -C "$dir" branch -a 2>/dev/null | wc -l || echo "0")
    
    local tags
    tags=$(git -C "$dir" tag 2>/dev/null | wc -l || echo "0")
    
    echo "  Total commits: $total_commits"
    echo "  Branches: $branches"
    echo "  Tags: $tags"
    echo ""
}

get_author_stats() {
    local dir="$1"
    
    if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo -e "${YELLOW}Not a git repository - author statistics unavailable${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Author Statistics:${NC}"
    
    git -C "$dir" shortlog -sn --all 2>/dev/null | head -10 | while read -r commits author; do
        echo "  $author: $commits commits"
    done
    echo ""
}

get_timeline_stats() {
    local dir="$1"
    
    if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo -e "${YELLOW}Not a git repository - timeline unavailable${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Development Timeline (Last 12 months):${NC}"
    
    local months=()
    local counts=()
    
    for i in {11..0}; do
        local month_start
        local month_end
        
        if date --version 2>/dev/null | grep -q GNU; then
            month_start=$(date -d "$i months ago" '+%Y-%m-01')
            month_end=$(date -d "$((i-1)) months ago" '+%Y-%m-01')
        else
            month_start=$(date -v-"$i"m '+%Y-%m-01')
            month_end=$(date -v-"$((i-1))"m '+%Y-%m-01')
        fi
        
        local count
        count=$(git -C "$dir" rev-list --count --since="$month_start" --until="$month_end" --all 2>/dev/null || echo "0")
        
        local month_name
        if date --version 2>/dev/null | grep -q GNU; then
            month_name=$(date -d "$month_start" '+%Y-%m')
        else
            month_name=$(date -j -f '%Y-%m-%d' "$month_start" '+%Y-%m')
        fi
        
        months+=("$month_name")
        counts+=("$count")
        
        printf "  %-7s: " "$month_name"
        
        # Simple bar chart
        local bar_length=$((count / 5))
        if [[ $bar_length -gt 50 ]]; then bar_length=50; fi
        
        for ((j=0; j<bar_length; j++)); do
            printf "▓"
        done
        printf " (%d commits)\n" "$count"
    done
    echo ""
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

output_text_format() {
    local analysis_result="$1"
    local show_languages="$2"
    local detailed="$3"
    
    local summary_line
    summary_line=$(echo "$analysis_result" | grep "^SUMMARY:")
    
    IFS=':' read -r _ total_files total_size total_lines total_code_lines total_comment_lines <<< "$summary_line"
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}              CODE STATISTICS${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Directory: $(pwd)"
    echo "Analysis date: $(date)"
    echo ""
    
    echo -e "${BLUE}Overall Statistics:${NC}"
    echo "  Total files: $total_files"
    echo "  Total size: $(format_size "$total_size")"
    echo "  Total lines: $total_lines"
    echo "  Code lines: $total_code_lines"
    echo "  Comment lines: $total_comment_lines"
    echo "  Blank lines: $((total_lines - total_code_lines - total_comment_lines))"
    echo ""
    
    if [[ "$show_languages" == "true" ]]; then
        echo -e "${BLUE}Statistics by Language:${NC}"
        echo "$analysis_result" | grep "^LANGUAGE:" | sort -t: -k3 -nr | while IFS=':' read -r _ language files size lines code_lines comment_lines; do
            local percentage
            if [[ $total_code_lines -gt 0 ]]; then
                percentage=$((code_lines * 100 / total_code_lines))
            else
                percentage=0
            fi
            
            echo -e "${CYAN}  $language:${NC}"
            echo "    Files: $files"
            echo "    Size: $(format_size "$size")"
            echo "    Total lines: $lines"
            echo "    Code lines: $code_lines (${percentage}%)"
            echo "    Comments: $comment_lines"
            echo ""
        done
    fi
    
    if [[ "$detailed" == "true" ]]; then
        echo -e "${BLUE}Detailed File Statistics:${NC}"
        echo "$analysis_result" | grep "^FILE:" | sort -t: -k4 -nr | head -20 | while IFS=':' read -r _ file language size lines code_lines comment_lines; do
            echo -e "${CYAN}  $(basename "$file"):${NC}"
            echo "    Path: $file"
            echo "    Language: $language"
            echo "    Size: $(format_size "$size")"
            echo "    Lines: $lines (code: $code_lines, comments: $comment_lines)"
            echo ""
        done
    fi
}

output_json_format() {
    local analysis_result="$1"
    local show_languages="$2"
    local detailed="$3"
    
    local summary_line
    summary_line=$(echo "$analysis_result" | grep "^SUMMARY:")
    IFS=':' read -r _ total_files total_size total_lines total_code_lines total_comment_lines <<< "$summary_line"
    
    echo "{"
    echo "  \"summary\": {"
    echo "    \"total_files\": $total_files,"
    echo "    \"total_size\": $total_size,"
    echo "    \"total_lines\": $total_lines,"
    echo "    \"code_lines\": $total_code_lines,"
    echo "    \"comment_lines\": $total_comment_lines,"
    echo "    \"blank_lines\": $((total_lines - total_code_lines - total_comment_lines))"
    echo "  },"
    
    if [[ "$show_languages" == "true" ]]; then
        echo "  \"languages\": ["
        local first=true
        echo "$analysis_result" | grep "^LANGUAGE:" | while IFS=':' read -r _ language files size lines code_lines comment_lines; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    {"
            echo -n "\"name\": \"$language\", "
            echo -n "\"files\": $files, "
            echo -n "\"size\": $size, "
            echo -n "\"lines\": $lines, "
            echo -n "\"code_lines\": $code_lines, "
            echo -n "\"comment_lines\": $comment_lines"
            echo -n "}"
        done
        echo ""
        echo "  ]"
    fi
    
    echo "}"
}

main() {
    local directory="$(pwd)"
    local detailed=false
    local show_languages=false
    local show_authors=false
    local show_timeline=false
    local exclude_pattern=""
    local output_format="text"
    local min_size="1"
    local max_depth=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                ;;
            -d|--detailed)
                detailed=true
                shift
                ;;
            -l|--languages)
                show_languages=true
                shift
                ;;
            -a|--authors)
                show_authors=true
                shift
                ;;
            -t|--timeline)
                show_timeline=true
                shift
                ;;
            -e|--exclude)
                exclude_pattern="$2"
                shift 2
                ;;
            -o|--output)
                output_format="$2"
                shift 2
                ;;
            --min-size)
                min_size="$2"
                shift 2
                ;;
            --max-depth)
                max_depth="$2"
                shift 2
                ;;
            --version)
                echo "code_stats.sh version $SCRIPT_VERSION"
                exit 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                print_usage
                ;;
            *)
                directory="$1"
                shift
                ;;
        esac
    done
    
    if [[ ! -d "$directory" ]]; then
        echo -e "${RED}Error: Directory does not exist: $directory${NC}"
        exit 1
    fi
    
    cd "$directory"
    
    echo -e "${CYAN}Analyzing code statistics...${NC}"
    
    local analysis_result
    analysis_result=$(analyze_directory "$directory" "$exclude_pattern" "$min_size" "$max_depth" "$detailed")
    
    case "$output_format" in
        text)
            output_text_format "$analysis_result" "$show_languages" "$detailed"
            ;;
        json)
            output_json_format "$analysis_result" "$show_languages" "$detailed"
            ;;
        csv)
            echo "format,files,size,lines,code_lines,comment_lines"
            echo "$analysis_result" | grep "^LANGUAGE:" | while IFS=':' read -r _ language files size lines code_lines comment_lines; do
                echo "$language,$files,$size,$lines,$code_lines,$comment_lines"
            done
            ;;
    esac
    
    if [[ "$output_format" == "text" ]]; then
        if [[ "$show_authors" == "true" ]]; then
            get_author_stats "$directory"
        fi
        
        if [[ "$show_timeline" == "true" ]]; then
            get_timeline_stats "$directory"
        fi
        
        get_git_stats "$directory"
        
        echo -e "${BLUE}================================================${NC}"
        echo -e "${GREEN}Analysis completed at $(date)${NC}"
        echo -e "${BLUE}================================================${NC}"
    fi
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    main "$@"
fi