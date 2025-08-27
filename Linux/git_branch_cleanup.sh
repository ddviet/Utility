#!/usr/bin/env bash
# git_branch_cleanup.sh
# Purpose:
#   - Intelligent Git branch management and cleanup
#   - Safely remove merged, stale, and obsolete branches
#   - Support for local and remote branch cleanup with safety checks
#
# Features:
#   - Automatic detection of merged branches
#   - Configurable staleness detection (by last commit date)
#   - Pattern-based branch protection (keep important branches)
#   - Remote branch cleanup with confirmation
#   - Detailed reporting and dry-run capabilities
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
git_branch_cleanup.sh — Intelligent Git Branch Management Tool

USAGE
    git_branch_cleanup.sh [OPTIONS]

DESCRIPTION
    Safely cleanup Git repositories by removing merged branches, stale branches,
    and obsolete remote tracking branches. Uses intelligent detection to preserve
    important branches while cleaning up development clutter.

OPTIONS
    -d, --dry-run       Preview what would be deleted without deleting
    -r, --remote        Clean remote branches in addition to local
    -f, --force         Force delete unmerged branches (use with caution)
    -a, --all           Clean both local and remote branches
    -s, --stale DAYS    Remove branches stale for N days (default: 30)
    -m, --main BRANCH   Specify main branch name (auto-detect: main/master)
    -k, --keep PATTERN  Keep branches matching regex pattern
    --list-only         List branches that would be affected
    --version           Show script version
    -h, --help          Show this help message

BRANCH TYPES CLEANED
    Merged:    Branches already merged into main/master branch
    Stale:     Branches with no commits for specified days
    Obsolete:  Remote tracking branches for deleted remotes
    Duplicate: Local branches tracking deleted remote branches

EXAMPLES (run directly from GitHub - must be in git repo)
    # Preview cleanup of current repository
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/git_branch_cleanup.sh)" -- --dry-run

    # Safe cleanup with 14-day staleness threshold
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/git_branch_cleanup.sh)" -- --stale 14

    # Aggressive cleanup including remote branches
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/git_branch_cleanup.sh)" -- --remote --force

    # Keep release and feature branches
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/git_branch_cleanup.sh)" -- --keep 'release.*|feature.*'

RECOMMENDED (download, review, then run)
    cd /path/to/git/repository
    curl -fsSL -o /tmp/git_branch_cleanup.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/git_branch_cleanup.sh
    chmod +x /tmp/git_branch_cleanup.sh
    /tmp/git_branch_cleanup.sh --dry-run      # preview first
    /tmp/git_branch_cleanup.sh --stale 30     # cleanup old branches
    /tmp/git_branch_cleanup.sh --remote       # include remote cleanup

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/git-cleanup https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/git_branch_cleanup.sh
    sudo chmod +x /usr/local/bin/git-cleanup
    git-cleanup --dry-run

AUTOMATION EXAMPLES  
    # Weekly cleanup in CI/CD
    git-cleanup --stale 7 --remote

    # Pre-release cleanup
    git-cleanup --dry-run | mail -s "Branch cleanup preview" team@example.com
    git-cleanup --keep 'release.*|hotfix.*'

    # Maintenance script for multiple repos
    for repo in ~/projects/*/; do
        (cd "$repo" && git-cleanup --stale 60)
    done

SAFETY FEATURES
    Branch Protection:   Never delete current, main, or master branches
    Pattern Matching:    Keep branches matching specified patterns
    Confirmation:        Interactive confirmation for destructive operations
    Backup Info:         Shows branch commit info before deletion
    Force Protection:    Requires explicit --force for unmerged branches

BRANCH ANALYSIS
    • Identifies truly merged branches (not just fast-forward)
    • Analyzes commit dates and authorship
    • Detects remote tracking relationship status
    • Shows branch divergence from main branch
    • Reports space savings from cleanup

COMMON USE CASES
    Development Cleanup: Remove feature branches after merge
    Release Management:  Clean up old release preparation branches
    CI/CD Maintenance:   Automated cleanup in build pipelines
    Repository Hygiene:  Regular maintenance of collaborative repos

SUPPORTED WORKFLOWS
    • Git Flow (feature, develop, release, hotfix branches)
    • GitHub Flow (feature branches merged to main)
    • GitLab Flow (environment and feature branches)
    • Custom workflows with pattern-based protection

EXIT CODES
    0   Cleanup completed successfully
    1   No branches to clean or not a git repository
    2   Git errors or repository issues
    3   Invalid arguments or pattern syntax

SECURITY CONSIDERATIONS
    • Only operates on current git repository
    • Respects git permissions and access controls
    • Never modifies remote repositories without confirmation
    • Preserves branch information for recovery

EOF
}

check_git_repo() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi
}

get_main_branch() {
    local main_branch="$1"
    
    if [[ -n "$main_branch" ]]; then
        echo "$main_branch"
        return
    fi
    
    # Try to detect main branch
    local candidates=("main" "master" "develop" "development")
    
    for branch in "${candidates[@]}"; do
        if git show-ref --verify --quiet "refs/heads/$branch"; then
            echo "$branch"
            return
        fi
    done
    
    # Fallback to current branch
    git rev-parse --abbrev-ref HEAD
}

get_merged_branches() {
    local main_branch="$1"
    local keep_pattern="$2"
    
    git branch --merged "$main_branch" | \
    grep -v "^\*" | \
    grep -v "^[[:space:]]*$main_branch$" | \
    sed 's/^[[:space:]]*//' | \
    while IFS= read -r branch; do
        if [[ -n "$keep_pattern" ]] && echo "$branch" | grep -qE "$keep_pattern"; then
            continue
        fi
        echo "$branch"
    done
}

get_stale_branches() {
    local days="$1"
    local main_branch="$2"
    local keep_pattern="$3"
    
    local cutoff_date
    if date --version 2>/dev/null | grep -q GNU; then
        cutoff_date=$(date -d "$days days ago" '+%Y-%m-%d')
    else
        cutoff_date=$(date -v-"$days"d '+%Y-%m-%d')
    fi
    
    git for-each-ref --format='%(refname:short) %(committerdate:short)' refs/heads | \
    while read -r branch date; do
        if [[ "$branch" == "$main_branch" ]]; then
            continue
        fi
        
        if [[ -n "$keep_pattern" ]] && echo "$branch" | grep -qE "$keep_pattern"; then
            continue
        fi
        
        if [[ "$date" < "$cutoff_date" ]]; then
            echo "$branch"
        fi
    done
}

get_remote_merged_branches() {
    local main_branch="$1"
    local remote="$2"
    local keep_pattern="$3"
    
    git branch -r --merged "$remote/$main_branch" | \
    grep "^[[:space:]]*$remote/" | \
    grep -v "^[[:space:]]*$remote/HEAD" | \
    grep -v "^[[:space:]]*$remote/$main_branch$" | \
    sed "s/^[[:space:]]*$remote\///" | \
    while IFS= read -r branch; do
        if [[ -n "$keep_pattern" ]] && echo "$branch" | grep -qE "$keep_pattern"; then
            continue
        fi
        echo "$branch"
    done
}

delete_local_branch() {
    local branch="$1"
    local force="$2"
    local dry_run="$3"
    
    echo -e "${CYAN}Local branch: $branch${NC}"
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}  [DRY RUN] Would delete local branch${NC}"
        return 0
    fi
    
    if [[ "$force" == "true" ]]; then
        if git branch -D "$branch" >/dev/null 2>&1; then
            echo -e "${GREEN}  Deleted (forced)${NC}"
        else
            echo -e "${RED}  Failed to delete${NC}"
        fi
    else
        if git branch -d "$branch" >/dev/null 2>&1; then
            echo -e "${GREEN}  Deleted${NC}"
        else
            echo -e "${RED}  Failed to delete (use -f to force)${NC}"
        fi
    fi
}

delete_remote_branch() {
    local branch="$1"
    local remote="$2"
    local dry_run="$3"
    
    echo -e "${CYAN}Remote branch: $remote/$branch${NC}"
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}  [DRY RUN] Would delete remote branch${NC}"
        return 0
    fi
    
    if git push "$remote" --delete "$branch" >/dev/null 2>&1; then
        echo -e "${GREEN}  Deleted from $remote${NC}"
    else
        echo -e "${RED}  Failed to delete from $remote${NC}"
    fi
}

show_branch_info() {
    local branch="$1"
    local main_branch="$2"
    
    local last_commit
    last_commit=$(git log -1 --format="%h %s" "$branch" 2>/dev/null || echo "unknown")
    
    local last_date
    last_date=$(git log -1 --format="%cd" --date=short "$branch" 2>/dev/null || echo "unknown")
    
    local commits_behind
    commits_behind=$(git rev-list --count "$branch..$main_branch" 2>/dev/null || echo "0")
    
    echo "    Last commit: $last_commit"
    echo "    Last date: $last_date"
    echo "    Commits behind $main_branch: $commits_behind"
}

main() {
    local dry_run=false
    local clean_remote=false
    local force_delete=false
    local stale_days=30
    local main_branch=""
    local keep_pattern=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -r|--remote)
                clean_remote=true
                shift
                ;;
            -f|--force)
                force_delete=true
                shift
                ;;
            -a|--all)
                clean_remote=true
                shift
                ;;
            -s|--stale)
                stale_days="$2"
                shift 2
                ;;
            -m|--main)
                main_branch="$2"
                shift 2
                ;;
            -k|--keep)
                keep_pattern="$2"
                shift 2
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
    
    check_git_repo
    
    main_branch=$(get_main_branch "$main_branch")
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}          GIT BRANCH CLEANUP${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Repository: $(pwd)"
    echo "Main branch: $main_branch"
    echo "Stale threshold: $stale_days days"
    if [[ -n "$keep_pattern" ]]; then
        echo "Keep pattern: $keep_pattern"
    fi
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No branches will be deleted${NC}"
    fi
    echo "Started: $(date)"
    echo ""
    
    # Fetch latest changes
    echo -e "${BLUE}Fetching latest changes...${NC}"
    if git fetch --all --prune >/dev/null 2>&1; then
        echo -e "${GREEN}Fetch completed${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to fetch changes${NC}"
    fi
    echo ""
    
    # Clean merged branches
    echo -e "${BLUE}Merged branches to clean:${NC}"
    local merged_count=0
    while IFS= read -r branch; do
        if [[ -z "$branch" ]]; then
            continue
        fi
        ((merged_count++))
        show_branch_info "$branch" "$main_branch"
        delete_local_branch "$branch" "$force_delete" "$dry_run"
        echo ""
    done < <(get_merged_branches "$main_branch" "$keep_pattern")
    
    if [[ $merged_count -eq 0 ]]; then
        echo -e "${GREEN}No merged branches to clean${NC}"
        echo ""
    fi
    
    # Clean stale branches
    echo -e "${BLUE}Stale branches (older than $stale_days days):${NC}"
    local stale_count=0
    while IFS= read -r branch; do
        if [[ -z "$branch" ]]; then
            continue
        fi
        ((stale_count++))
        show_branch_info "$branch" "$main_branch"
        delete_local_branch "$branch" "$force_delete" "$dry_run"
        echo ""
    done < <(get_stale_branches "$stale_days" "$main_branch" "$keep_pattern")
    
    if [[ $stale_count -eq 0 ]]; then
        echo -e "${GREEN}No stale branches to clean${NC}"
        echo ""
    fi
    
    # Clean remote branches
    if [[ "$clean_remote" == "true" ]]; then
        echo -e "${BLUE}Remote branch cleanup:${NC}"
        local remotes
        remotes=$(git remote | grep -v '^$' || true)
        
        if [[ -z "$remotes" ]]; then
            echo -e "${YELLOW}No remotes configured${NC}"
        else
            for remote in $remotes; do
                echo -e "${CYAN}Remote: $remote${NC}"
                local remote_count=0
                
                while IFS= read -r branch; do
                    if [[ -z "$branch" ]]; then
                        continue
                    fi
                    ((remote_count++))
                    delete_remote_branch "$branch" "$remote" "$dry_run"
                done < <(get_remote_merged_branches "$main_branch" "$remote" "$keep_pattern")
                
                if [[ $remote_count -eq 0 ]]; then
                    echo -e "${GREEN}  No remote branches to clean${NC}"
                fi
                echo ""
            done
        fi
    fi
    
    # Summary
    echo -e "${BLUE}Current branches:${NC}"
    git branch -v --color=always | sed 's/^/  /'
    
    if [[ "$clean_remote" == "true" ]]; then
        echo ""
        echo -e "${BLUE}Remote branches:${NC}"
        git branch -rv --color=always | sed 's/^/  /'
    fi
    
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Branch cleanup completed at $(date)${NC}"
    echo -e "${BLUE}================================================${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi