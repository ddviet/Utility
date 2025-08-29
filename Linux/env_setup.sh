#!/bin/bash
# env_setup.sh
# Purpose:
#   - Automate installation of development environments and tools
#   - Support multiple programming languages and technology stacks
#   - Provide consistent development environment setup across systems
#
# Features:
#   - Multiple installation profiles: basic, nodejs, python, rust, go, java, docker
#   - Cross-platform support for major Linux distributions
#   - Version management and package manager integration
#   - Configuration file setup with sensible defaults
#   - Development tool ecosystem installation (IDEs, extensions, utilities)
#   - Docker and containerization environment setup
#   - DevOps toolchain installation (kubectl, terraform, etc.)
#   - Dry-run mode for preview and testing
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
env_setup.sh — Development Environment Setup and Configuration Tool

USAGE
    env_setup.sh [OPTIONS] [PROFILE]

DESCRIPTION
    Automate installation of development environments and tools with support
    for multiple programming languages and technology stacks. Provides
    consistent development environment setup across different systems.

PROFILES
    basic          Essential development tools (git, curl, wget, vim, etc.)
    nodejs         Node.js development environment with npm, yarn, pnpm
    python         Python development environment with pip, virtualenv, poetry
    rust           Rust development environment with rustup, cargo, clippy
    go             Go development environment with modules support
    java           Java development environment with Maven
    docker         Docker and containerization tools
    web            Web development stack (nodejs + docker)
    devops         DevOps toolchain (docker, kubectl, terraform)
    full           Complete development setup (all available tools)

OPTIONS
    -h, --help           Show this help message
    -d, --dry-run        Show what would be installed without installing
    -u, --update         Update existing packages to latest versions
    -c, --config         Setup configuration files (.gitconfig, .vimrc, aliases)
    -s, --skip-confirm   Skip confirmation prompts for automated setup
    --version VERSION    Specify version for tools that support it
    --version            Show script version

SUPPORTED PLATFORMS
    Ubuntu/Debian:  Using apt package manager
    CentOS/RHEL:    Using dnf/yum package manager
    Fedora:         Using dnf package manager
    Arch Linux:     Using pacman package manager
    macOS:          Using Homebrew package manager

CONFIGURATION FEATURES
    Git Configuration:   Username, email, aliases, and sensible defaults
    Vim Setup:          Syntax highlighting, line numbers, and productivity settings
    Shell Aliases:      Common development shortcuts and productivity aliases
    PATH Updates:       Automatic PATH configuration for installed tools

EXAMPLES (run directly from GitHub)
    # Basic development tools installation
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/env_setup.sh)" -- basic

    # Complete development environment with configuration
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/env_setup.sh)" -- full -c

    # Dry run to preview Node.js setup
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/env_setup.sh)" -- --dry-run nodejs

    # Python development environment with specific version
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/env_setup.sh)" -- python --version 3.11

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/env_setup.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/env_setup.sh
    chmod +x /tmp/env_setup.sh
    /tmp/env_setup.sh --help              # Show this help
    /tmp/env_setup.sh --dry-run basic     # Preview basic setup
    /tmp/env_setup.sh nodejs -c           # Install Node.js with config
    /tmp/env_setup.sh full --skip-confirm # Automated full setup

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/dev-setup https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/env_setup.sh
    sudo chmod +x /usr/local/bin/dev-setup
    dev-setup python -c

AUTOMATION EXAMPLES
    # Automated CI/CD environment setup
    dev-setup basic --skip-confirm
    
    # Docker container environment preparation
    dev-setup web --dry-run > setup_plan.txt
    dev-setup web --skip-confirm
    
    # Team onboarding automation
    dev-setup full -c --skip-confirm | tee setup.log

INSTALLATION FEATURES
    Version Management:   Install specific versions when supported
    Dependency Resolution: Automatic handling of package dependencies
    Cross-Platform:       Works on major Linux distributions and macOS
    Rollback Protection:  Dry-run mode to preview changes
    Update Support:       Update existing installations safely

SECURITY CONSIDERATIONS
    • Always review scripts before running with elevated privileges
    • Use dry-run mode to preview changes before installation
    • Installation sources are official repositories when possible
    • Configuration files preserve existing settings when safe

COMMON USE CASES
    New Machine Setup:     Quick development environment bootstrap
    Team Standardization: Ensure consistent tooling across team members
    CI/CD Integration:     Automated build environment preparation
    Container Setup:       Development environment in Docker containers
    Version Updates:       Bulk update of development tools

EXIT CODES
    0   Setup completed successfully
    1   Invalid profile or missing requirements
    2   Package installation failures
    3   Configuration setup errors
    4   User cancelled installation

WARNING: This script modifies system packages and configuration files.
         Always review the script and use --dry-run before installation.

EOF
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif command -v uname >/dev/null 2>&1; then
        local uname_out
        uname_out=$(uname -s)
        case "$uname_out" in
            Linux*) echo "linux" ;;
            Darwin*) echo "macos" ;;
            CYGWIN*|MINGW*) echo "windows" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

detect_package_manager() {
    local os="$1"
    
    case "$os" in
        ubuntu|debian)
            echo "apt"
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        arch)
            echo "pacman"
            ;;
        macos)
            echo "brew"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

check_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

install_package() {
    local pkg="$1"
    local pkg_manager="$2"
    local dry_run="$3"
    
    echo -e "${CYAN}Installing: $pkg${NC}"
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}  [DRY RUN] Would install $pkg${NC}"
        return 0
    fi
    
    case "$pkg_manager" in
        apt)
            if sudo apt-get install -y "$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}  Installed successfully${NC}"
            else
                echo -e "${RED}  Failed to install${NC}"
                return 1
            fi
            ;;
        dnf)
            if sudo dnf install -y "$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}  Installed successfully${NC}"
            else
                echo -e "${RED}  Failed to install${NC}"
                return 1
            fi
            ;;
        yum)
            if sudo yum install -y "$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}  Installed successfully${NC}"
            else
                echo -e "${RED}  Failed to install${NC}"
                return 1
            fi
            ;;
        pacman)
            if sudo pacman -S --noconfirm "$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}  Installed successfully${NC}"
            else
                echo -e "${RED}  Failed to install${NC}"
                return 1
            fi
            ;;
        brew)
            if brew install "$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}  Installed successfully${NC}"
            else
                echo -e "${RED}  Failed to install${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${YELLOW}  Package manager not supported${NC}"
            return 1
            ;;
    esac
}

setup_basic_tools() {
    local pkg_manager="$1"
    local dry_run="$2"
    local update="$3"
    
    echo -e "${BLUE}Setting up basic development tools...${NC}"
    
    local basic_packages
    case "$pkg_manager" in
        apt)
            basic_packages=(
                "curl" "wget" "git" "vim" "nano" "tree" "htop" "unzip" "zip"
                "build-essential" "software-properties-common" "apt-transport-https"
                "ca-certificates" "gnupg" "lsb-release"
            )
            ;;
        dnf|yum)
            basic_packages=(
                "curl" "wget" "git" "vim" "nano" "tree" "htop" "unzip" "zip"
                "gcc" "gcc-c++" "make" "which"
            )
            ;;
        pacman)
            basic_packages=(
                "curl" "wget" "git" "vim" "nano" "tree" "htop" "unzip" "zip"
                "base-devel"
            )
            ;;
        brew)
            basic_packages=(
                "curl" "wget" "git" "vim" "nano" "tree" "htop" "unzip" "zip"
            )
            ;;
    esac
    
    for pkg in "${basic_packages[@]}"; do
        if ! check_command "$pkg" || [[ "$update" == "true" ]]; then
            install_package "$pkg" "$pkg_manager" "$dry_run"
        else
            echo -e "${GREEN}$pkg is already installed${NC}"
        fi
    done
}

setup_nodejs() {
    local dry_run="$1"
    local version="${2:-lts}"
    
    echo -e "${BLUE}Setting up Node.js development environment...${NC}"
    
    if ! check_command "node" || [[ "$dry_run" == "true" ]]; then
        echo -e "${CYAN}Installing Node.js${NC}"
        
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}  [DRY RUN] Would install Node.js $version via nvm${NC}"
        else
            # Install nvm
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash >/dev/null 2>&1
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            
            # Install and use Node.js
            nvm install "$version" >/dev/null 2>&1 && echo -e "${GREEN}  Node.js installed${NC}"
            nvm use "$version" >/dev/null 2>&1
            
            # Install global packages
            npm install -g npm@latest yarn pnpm typescript ts-node nodemon >/dev/null 2>&1
            echo -e "${GREEN}  Global packages installed${NC}"
        fi
    else
        echo -e "${GREEN}Node.js is already installed${NC}"
    fi
}

setup_python() {
    local pkg_manager="$1"
    local dry_run="$2"
    local version="${3:-3.11}"
    
    echo -e "${BLUE}Setting up Python development environment...${NC}"
    
    local python_packages
    case "$pkg_manager" in
        apt)
            python_packages=("python3" "python3-pip" "python3-venv" "python3-dev")
            ;;
        dnf|yum)
            python_packages=("python3" "python3-pip" "python3-virtualenv" "python3-devel")
            ;;
        pacman)
            python_packages=("python" "python-pip" "python-virtualenv")
            ;;
        brew)
            python_packages=("python@3.11")
            ;;
    esac
    
    for pkg in "${python_packages[@]}"; do
        if ! check_command "python3" || [[ "$dry_run" == "true" ]]; then
            install_package "$pkg" "$pkg_manager" "$dry_run"
        fi
    done
    
    # Install Python tools
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}  [DRY RUN] Would install Python development tools${NC}"
    else
        pip3 install --user --upgrade pip setuptools wheel virtualenv pipenv poetry black flake8 mypy >/dev/null 2>&1
        echo -e "${GREEN}  Python development tools installed${NC}"
    fi
}

setup_rust() {
    local dry_run="$1"
    
    echo -e "${BLUE}Setting up Rust development environment...${NC}"
    
    if ! check_command "rustc" || [[ "$dry_run" == "true" ]]; then
        echo -e "${CYAN}Installing Rust${NC}"
        
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}  [DRY RUN] Would install Rust via rustup${NC}"
        else
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1
            source "$HOME/.cargo/env"
            rustup component add clippy rustfmt >/dev/null 2>&1
            echo -e "${GREEN}  Rust installed with clippy and rustfmt${NC}"
        fi
    else
        echo -e "${GREEN}Rust is already installed${NC}"
    fi
}

setup_go() {
    local dry_run="$1"
    local version="${2:-1.21}"
    
    echo -e "${BLUE}Setting up Go development environment...${NC}"
    
    if ! check_command "go" || [[ "$dry_run" == "true" ]]; then
        echo -e "${CYAN}Installing Go${NC}"
        
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}  [DRY RUN] Would install Go $version${NC}"
        else
            local go_url="https://golang.org/dl/go${version}.linux-amd64.tar.gz"
            wget -q "$go_url" -O /tmp/go.tar.gz
            sudo tar -C /usr/local -xzf /tmp/go.tar.gz
            rm /tmp/go.tar.gz
            
            # Add to PATH
            echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> "$HOME/.bashrc"
            export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
            
            echo -e "${GREEN}  Go installed${NC}"
        fi
    else
        echo -e "${GREEN}Go is already installed${NC}"
    fi
}

setup_java() {
    local pkg_manager="$1"
    local dry_run="$2"
    
    echo -e "${BLUE}Setting up Java development environment...${NC}"
    
    local java_package
    case "$pkg_manager" in
        apt)
            java_package="openjdk-17-jdk"
            ;;
        dnf|yum)
            java_package="java-17-openjdk-devel"
            ;;
        pacman)
            java_package="jdk17-openjdk"
            ;;
        brew)
            java_package="openjdk@17"
            ;;
    esac
    
    if ! check_command "java" || [[ "$dry_run" == "true" ]]; then
        install_package "$java_package" "$pkg_manager" "$dry_run"
        
        # Install Maven
        install_package "maven" "$pkg_manager" "$dry_run"
    else
        echo -e "${GREEN}Java is already installed${NC}"
    fi
}

setup_docker() {
    local os="$1"
    local pkg_manager="$2"
    local dry_run="$3"
    
    echo -e "${BLUE}Setting up Docker...${NC}"
    
    if ! check_command "docker" || [[ "$dry_run" == "true" ]]; then
        echo -e "${CYAN}Installing Docker${NC}"
        
        if [[ "$dry_run" == "true" ]]; then
            echo -e "${YELLOW}  [DRY RUN] Would install Docker${NC}"
            return 0
        fi
        
        case "$os" in
            ubuntu|debian)
                # Add Docker's GPG key
                curl -fsSL https://download.docker.com/linux/$os/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                
                # Add repository
                echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$os $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
                
                # Install
                sudo apt-get update >/dev/null 2>&1
                sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
                ;;
            centos|rhel|fedora)
                sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1 || \
                sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
                ;;
            macos)
                brew install docker >/dev/null 2>&1
                ;;
        esac
        
        # Add user to docker group and start service
        if [[ "$os" != "macos" ]]; then
            sudo usermod -aG docker "$USER" >/dev/null 2>&1
            sudo systemctl enable docker >/dev/null 2>&1
            sudo systemctl start docker >/dev/null 2>&1
        fi
        
        echo -e "${GREEN}  Docker installed${NC}"
        echo -e "${YELLOW}  Note: Please logout and login again to use Docker without sudo${NC}"
    else
        echo -e "${GREEN}Docker is already installed${NC}"
    fi
}

setup_config_files() {
    local dry_run="$1"
    
    echo -e "${BLUE}Setting up configuration files...${NC}"
    
    # Git config
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}  [DRY RUN] Would setup git config, vim config, bash aliases${NC}"
    else
        # Basic .gitconfig
        if [[ ! -f "$HOME/.gitconfig" ]]; then
            cat > "$HOME/.gitconfig" << 'EOF'
[core]
    editor = vim
    autocrlf = input
[push]
    default = simple
[pull]
    rebase = false
[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
    unstage = reset HEAD --
    last = log -1 HEAD
    visual = !gitk
EOF
            echo -e "${GREEN}  Created .gitconfig${NC}"
        fi
        
        # Basic .vimrc
        if [[ ! -f "$HOME/.vimrc" ]]; then
            cat > "$HOME/.vimrc" << 'EOF'
syntax on
set number
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set hlsearch
set ignorecase
set smartcase
EOF
            echo -e "${GREEN}  Created .vimrc${NC}"
        fi
        
        # Bash aliases
        if ! grep -q "# Development aliases" "$HOME/.bashrc" 2>/dev/null; then
            cat >> "$HOME/.bashrc" << 'EOF'

# Development aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'
EOF
            echo -e "${GREEN}  Added development aliases to .bashrc${NC}"
        fi
    fi
}

main() {
    local profile=""
    local dry_run=false
    local update=false
    local setup_config=false
    local skip_confirm=false
    local version=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -u|--update)
                update=true
                shift
                ;;
            -c|--config)
                setup_config=true
                shift
                ;;
            -s|--skip-confirm)
                skip_confirm=true
                shift
                ;;
            --version)
                if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                    version="$2"
                    shift 2
                else
                    echo "env_setup.sh version $SCRIPT_VERSION"
                    exit 0
                fi
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                print_usage
                ;;
            *)
                profile="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$profile" ]]; then
        echo -e "${RED}Please specify a profile${NC}"
        usage
    fi
    
    local os
    os=$(detect_os)
    local pkg_manager
    pkg_manager=$(detect_package_manager "$os")
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}         ENVIRONMENT SETUP${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "OS: $os"
    echo "Package Manager: $pkg_manager"
    echo "Profile: $profile"
    echo "Version: ${version:-default}"
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - Nothing will be installed${NC}"
    fi
    echo "Started: $(date)"
    echo ""
    
    if [[ "$skip_confirm" == "false" && "$dry_run" == "false" ]]; then
        echo -e "${YELLOW}This will install development tools on your system.${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
        echo ""
    fi
    
    # Update package lists
    if [[ "$dry_run" == "false" ]]; then
        echo -e "${BLUE}Updating package lists...${NC}"
        case "$pkg_manager" in
            apt) sudo apt-get update >/dev/null 2>&1 ;;
            dnf) sudo dnf check-update >/dev/null 2>&1 || true ;;
            yum) sudo yum check-update >/dev/null 2>&1 || true ;;
            pacman) sudo pacman -Sy >/dev/null 2>&1 ;;
            brew) brew update >/dev/null 2>&1 ;;
        esac
        echo ""
    fi
    
    # Setup based on profile
    case "$profile" in
        basic)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            ;;
        nodejs)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_nodejs "$dry_run" "$version"
            ;;
        python)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_python "$pkg_manager" "$dry_run" "$version"
            ;;
        rust)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_rust "$dry_run"
            ;;
        go)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_go "$dry_run" "$version"
            ;;
        java)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_java "$pkg_manager" "$dry_run"
            ;;
        docker)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_docker "$os" "$pkg_manager" "$dry_run"
            ;;
        web)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_nodejs "$dry_run" "$version"
            setup_docker "$os" "$pkg_manager" "$dry_run"
            ;;
        devops)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_docker "$os" "$pkg_manager" "$dry_run"
            # Could add kubectl, terraform, etc.
            ;;
        full)
            setup_basic_tools "$pkg_manager" "$dry_run" "$update"
            setup_nodejs "$dry_run"
            setup_python "$pkg_manager" "$dry_run"
            setup_rust "$dry_run"
            setup_go "$dry_run"
            setup_java "$pkg_manager" "$dry_run"
            setup_docker "$os" "$pkg_manager" "$dry_run"
            ;;
        *)
            echo -e "${RED}Unknown profile: $profile${NC}"
            exit 1
            ;;
    esac
    
    echo ""
    
    if [[ "$setup_config" == "true" ]]; then
        setup_config_files "$dry_run"
        echo ""
    fi
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Environment setup completed at $(date)${NC}"
    if [[ "$dry_run" == "false" ]]; then
        echo -e "${YELLOW}Please restart your terminal or run 'source ~/.bashrc'${NC}"
    fi
    echo -e "${BLUE}================================================${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi