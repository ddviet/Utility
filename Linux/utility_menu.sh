#!/usr/bin/env bash
# utility_menu.sh
# Purpose:
#   - Interactive menu system for Linux Utility Toolkit
#   - Centralized access to all utility scripts with user-friendly interface
#   - Support for both local execution and remote GitHub execution
#
# Features:
#   - Colorful terminal UI with organized script categories
#   - Built-in help and documentation for each script
#   - Dependency checking and script validation
#   - Support for custom arguments and dry-run modes
#   - Remote execution examples for GitHub integration
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
WHITE='\033[1;37m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_banner() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}                            LINUX UTILITY TOOLKIT                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${WHITE}                         Comprehensive System Tools                          ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Current Directory: $(pwd)${NC}"
    echo -e "${CYAN}Script Location: $SCRIPT_DIR${NC}"
    echo -e "${CYAN}Date: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
}

show_main_menu() {
    echo -e "${BLUE}┌─────────────────────── MAIN MENU ───────────────────────┐${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}1${NC}) 🖥️  System Monitoring Tools                         ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}2${NC}) 💻 Development Utilities                            ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}3${NC}) 🔒 Network & Security Tools                        ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}4${NC}) 📁 File Management Utilities                        ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}h${NC}) 📖 Help & Documentation                            ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}q${NC}) 🚪 Quit                                            ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_system_menu() {
    echo -e "${BLUE}┌─────────────────── SYSTEM MONITORING ───────────────────┐${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}1${NC}) System Health Check      - CPU, memory, disk     ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}2${NC}) Port Scanner            - Check open ports       ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}3${NC}) Log Analyzer            - Analyze system logs    ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}4${NC}) Disk Cleanup            - Clean temp/cache files ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}b${NC}) ⬅️  Back to Main Menu                            ${BLUE}│${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_development_menu() {
    echo -e "${BLUE}┌─────────────────── DEVELOPMENT TOOLS ───────────────────┐${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}1${NC}) Git Branch Cleanup      - Clean merged branches  ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}2${NC}) Project Backup          - Backup code projects   ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}3${NC}) Environment Setup       - Install dev tools      ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}4${NC}) Code Statistics         - Analyze code metrics   ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}b${NC}) ⬅️  Back to Main Menu                            ${BLUE}│${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_network_menu() {
    echo -e "${BLUE}┌─────────────────── NETWORK & SECURITY ──────────────────┐${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}1${NC}) SSL Certificate Checker - Check cert expiration  ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}2${NC}) Network Information     - Show network config    ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}3${NC}) Backup Rotation         - Automated backups      ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}4${NC}) Service Monitor         - Monitor system services${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}b${NC}) ⬅️  Back to Main Menu                            ${BLUE}│${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_file_menu() {
    echo -e "${BLUE}┌──────────────────── FILE MANAGEMENT ────────────────────┐${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}1${NC}) Duplicate Finder        - Find duplicate files   ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}2${NC}) Batch Rename            - Rename files in bulk   ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}3${NC}) Permission Fixer        - Fix file permissions   ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}b${NC}) ⬅️  Back to Main Menu                            ${BLUE}│${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_help() {
    echo -e "${BLUE}┌─────────────────────── HELP & INFO ─────────────────────┐${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC} ${WHITE}Linux Utility Toolkit${NC}                                ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} A comprehensive collection of system administration    ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} and development utilities.                             ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC} ${WHITE}Features:${NC}                                           ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} • System health monitoring and diagnostics            ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} • Network analysis and security checks                ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} • Development environment management                  ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} • File system utilities and maintenance               ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} • Automated backup and rotation                       ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} • Service monitoring and management                   ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC} ${WHITE}Usage:${NC}                                              ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} All scripts can be run directly with --help for       ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} detailed usage information and examples.              ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC} ${WHITE}Available Scripts:${NC}                                 ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} system_health.sh, port_scanner.sh, log_analyzer.sh   ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} disk_cleanup.sh, git_branch_cleanup.sh               ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} project_backup.sh, env_setup.sh, code_stats.sh       ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} ssl_cert_checker.sh, network_info.sh                 ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} backup_rotation.sh, service_monitor.sh               ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} duplicate_finder.sh, batch_rename.sh                 ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} permission_fixer.sh                                   ${BLUE}│${NC}"
    echo -e "${BLUE}│                                                          │${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}b${NC}) ⬅️  Back to Main Menu                            ${BLUE}│${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

check_script_exists() {
    local script="$1"
    local script_path="$SCRIPT_DIR/$script"
    
    if [[ -f "$script_path" && -x "$script_path" ]]; then
        return 0
    else
        return 1
    fi
}

run_script() {
    local script="$1"
    local script_path="$SCRIPT_DIR/$script"
    
    echo -e "${CYAN}Running: $script${NC}"
    echo -e "${YELLOW}Press Enter to continue or Ctrl+C to cancel...${NC}"
    read -r
    
    if check_script_exists "$script"; then
        echo ""
        echo -e "${GREEN}Executing: $script_path${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo ""
        
        # Run the script and capture exit code
        if "$script_path" "$@"; then
            echo ""
            echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}✅ Script completed successfully${NC}"
        else
            echo ""
            echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
            echo -e "${RED}❌ Script finished with errors${NC}"
        fi
    else
        echo -e "${RED}❌ Script not found or not executable: $script_path${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

run_script_with_help() {
    local script="$1"
    local script_path="$SCRIPT_DIR/$script"
    
    echo -e "${CYAN}Script: $script${NC}"
    echo ""
    
    if check_script_exists "$script"; then
        echo -e "${WHITE}Available options:${NC}"
        echo -e "${GREEN}1${NC}) Run with default settings"
        echo -e "${GREEN}2${NC}) Show help and usage information"
        echo -e "${GREEN}3${NC}) Run with custom arguments"
        echo -e "${GREEN}b${NC}) Back to menu"
        echo ""
        
        while true; do
            read -p "Select option (1-3, b): " choice
            case $choice in
                1)
                    run_script "$script"
                    break
                    ;;
                2)
                    echo ""
                    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
                    "$script_path" --help || true
                    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
                    echo ""
                    echo -e "${YELLOW}Press Enter to continue...${NC}"
                    read -r
                    break
                    ;;
                3)
                    echo ""
                    read -p "Enter arguments for $script: " -r args
                    echo ""
                    run_script "$script" $args
                    break
                    ;;
                b|B)
                    break
                    ;;
                *)
                    echo -e "${RED}Invalid option. Please try again.${NC}"
                    ;;
            esac
        done
    else
        echo -e "${RED}❌ Script not found or not executable: $script_path${NC}"
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read -r
    fi
}

handle_system_menu() {
    while true; do
        show_banner
        show_system_menu
        
        read -p "Select an option: " choice
        case $choice in
            1)
                run_script_with_help "system_health.sh"
                ;;
            2)
                run_script_with_help "port_scanner.sh"
                ;;
            3)
                run_script_with_help "log_analyzer.sh"
                ;;
            4)
                run_script_with_help "disk_cleanup.sh"
                ;;
            b|B)
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

handle_development_menu() {
    while true; do
        show_banner
        show_development_menu
        
        read -p "Select an option: " choice
        case $choice in
            1)
                run_script_with_help "git_branch_cleanup.sh"
                ;;
            2)
                run_script_with_help "project_backup.sh"
                ;;
            3)
                run_script_with_help "env_setup.sh"
                ;;
            4)
                run_script_with_help "code_stats.sh"
                ;;
            b|B)
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

handle_network_menu() {
    while true; do
        show_banner
        show_network_menu
        
        read -p "Select an option: " choice
        case $choice in
            1)
                run_script_with_help "ssl_cert_checker.sh"
                ;;
            2)
                run_script_with_help "network_info.sh"
                ;;
            3)
                run_script_with_help "backup_rotation.sh"
                ;;
            4)
                run_script_with_help "service_monitor.sh"
                ;;
            b|B)
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

handle_file_menu() {
    while true; do
        show_banner
        show_file_menu
        
        read -p "Select an option: " choice
        case $choice in
            1)
                run_script_with_help "duplicate_finder.sh"
                ;;
            2)
                run_script_with_help "batch_rename.sh"
                ;;
            3)
                run_script_with_help "permission_fixer.sh"
                ;;
            b|B)
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

check_dependencies() {
    local missing_scripts=()
    local scripts=(
        "system_health.sh" "port_scanner.sh" "log_analyzer.sh" "disk_cleanup.sh"
        "git_branch_cleanup.sh" "project_backup.sh" "env_setup.sh" "code_stats.sh"
        "ssl_cert_checker.sh" "network_info.sh" "backup_rotation.sh" "service_monitor.sh"
        "duplicate_finder.sh" "batch_rename.sh" "permission_fixer.sh"
    )
    
    for script in "${scripts[@]}"; do
        if ! check_script_exists "$script"; then
            missing_scripts+=("$script")
        fi
    done
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Warning: Some scripts are missing or not executable:${NC}"
        for script in "${missing_scripts[@]}"; do
            echo -e "${RED}   ❌ $script${NC}"
        done
        echo ""
        echo -e "${YELLOW}Please ensure all scripts are in: $SCRIPT_DIR${NC}"
        echo -e "${YELLOW}And make them executable with: chmod +x *.sh${NC}"
        echo ""
        echo -e "${YELLOW}Press Enter to continue anyway...${NC}"
        read -r
    fi
}

main() {
    # Check if running in interactive mode
    if [[ ! -t 0 ]]; then
        echo "This script requires an interactive terminal."
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Main menu loop
    while true; do
        show_banner
        show_main_menu
        
        read -p "Select an option: " choice
        case $choice in
            1)
                handle_system_menu
                ;;
            2)
                handle_development_menu
                ;;
            3)
                handle_network_menu
                ;;
            4)
                handle_file_menu
                ;;
            h|H)
                show_banner
                show_help
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            q|Q)
                echo ""
                echo -e "${GREEN}Thank you for using Linux Utility Toolkit!${NC}"
                echo -e "${CYAN}Have a great day! 👋${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Handle command line arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help)
            echo "Linux Utility Toolkit - Interactive Menu"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -h, --help    Show this help message"
            echo "  --list        List all available scripts"
            echo ""
            echo "Interactive mode (default):"
            echo "  Run the script without arguments to start the interactive menu."
            exit 0
            ;;
        --list)
            echo "Available utility scripts:"
            echo ""
            echo "System Monitoring:"
            echo "  • system_health.sh    - System health check"
            echo "  • port_scanner.sh     - Network port scanner"
            echo "  • log_analyzer.sh     - System log analyzer"
            echo "  • disk_cleanup.sh     - Disk cleanup utility"
            echo ""
            echo "Development Tools:"
            echo "  • git_branch_cleanup.sh - Git branch management"
            echo "  • project_backup.sh   - Project backup utility"
            echo "  • env_setup.sh        - Development environment setup"
            echo "  • code_stats.sh       - Code statistics analyzer"
            echo ""
            echo "Network & Security:"
            echo "  • ssl_cert_checker.sh - SSL certificate checker"
            echo "  • network_info.sh     - Network information display"
            echo "  • backup_rotation.sh  - Automated backup rotation"
            echo "  • service_monitor.sh  - System service monitor"
            echo ""
            echo "File Management:"
            echo "  • duplicate_finder.sh - Duplicate file finder"
            echo "  • batch_rename.sh     - Batch file renaming"
            echo "  • permission_fixer.sh - File permission fixer"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use $0 --help for usage information."
            exit 1
            ;;
    esac
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi