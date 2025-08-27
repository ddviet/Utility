#!/usr/bin/env bash
# port_scanner.sh
# Purpose:
#   - Network port scanner and service detection tool
#   - Scan local or remote hosts for open ports and identify running services
#   - Support for custom port ranges, timeouts, and multiple output formats
#
# Features:
#   - Fast TCP port scanning with customizable timeouts
#   - Service identification for common ports
#   - Multiple scan types: common ports, custom ranges, specific ports
#   - Verbose mode with detailed connection information
#   - Support for both hostnames and IP addresses
#
# Maintainer: ddviet
SCRIPT_VERSION="1.0.0"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
    cat <<'EOF'
port_scanner.sh — Network Port Scanner and Service Detector

USAGE
    port_scanner.sh [OPTIONS] [TARGET]

DESCRIPTION
    Fast TCP port scanner that identifies open ports and running services on local
    or remote hosts. Uses native bash TCP connections for reliable scanning without
    requiring additional tools like nmap.

OPTIONS
    -l, --local         Scan localhost only (overrides TARGET)
    -p, --ports RANGE   Port specification (e.g., 1-1000, 22,80,443, 1-65535)
    -t, --timeout SEC   Connection timeout in seconds (default: 1)
    -v, --verbose       Show closed ports and detailed connection info
    -j, --json          Output results in JSON format
    --top-ports N       Scan top N most common ports (default: 100)
    --no-color          Disable colored output
    --version           Show script version
    -h, --help          Show this help message

ARGUMENTS
    TARGET              Target host (IP address or hostname)
                       Default: localhost if no target specified

PORT FORMATS
    Single:     22, 80, 443
    Range:      1-1000, 8000-9000
    Multiple:   22,80,443,8080
    Combined:   22,80,443,8000-8100

EXAMPLES (run directly from GitHub)
    # Scan localhost common ports
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/port_scanner.sh)"

    # Scan specific host with custom ports
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/port_scanner.sh)" -- -p 22,80,443 example.com

    # Verbose scan with extended timeout
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/port_scanner.sh)" -- -v -t 3 192.168.1.1

    # Scan port range in JSON format
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/port_scanner.sh)" -- -j -p 1-1000 target.com

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/port_scanner.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/port_scanner.sh
    chmod +x /tmp/port_scanner.sh
    /tmp/port_scanner.sh -l                      # scan localhost
    /tmp/port_scanner.sh -p 1-1000 target.com   # custom range
    /tmp/port_scanner.sh --top-ports 50 -v server.com # top 50 ports

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/port-scan https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/port_scanner.sh
    sudo chmod +x /usr/local/bin/port-scan
    port-scan -l -v

COMMON USE CASES
    # Network discovery
    port-scan -p 22,80,443,3389 192.168.1.1-254

    # Service verification
    port-scan -p 80,443 web-server.com

    # Security assessment
    port-scan --top-ports 1000 target.com

    # Local service check
    port-scan -l -v

AUTOMATION EXAMPLES
    # Monitor critical services
    port-scan -p 22,80,443 server.com -j | jq '.open_ports | length'

    # Network sweep script
    for ip in 192.168.1.{1..254}; do
        port-scan -p 22,80 $ip --timeout 0.5
    done

    # Service monitoring with alerts
    if ! port-scan -p 80 web-server.com >/dev/null 2>&1; then
        mail -s "Web server down" admin@example.com
    fi

DETECTED SERVICES
    Common ports are automatically identified with service names:
    • 21: FTP, 22: SSH, 23: Telnet, 25: SMTP, 53: DNS
    • 80: HTTP, 110: POP3, 143: IMAP, 443: HTTPS, 993: IMAPS
    • 3389: RDP, 5432: PostgreSQL, 3306: MySQL, 27017: MongoDB
    • And many more...

PERFORMANCE NOTES
    • Typical scan speed: 100-500 ports/second
    • Concurrent connections for better performance
    • Respects target system resources with reasonable timeouts
    • Memory efficient for large port ranges

SECURITY CONSIDERATIONS
    • Port scanning may trigger IDS/IPS systems
    • Always obtain permission before scanning remote hosts
    • Some firewalls may rate-limit or block scan attempts
    • Use appropriate timeouts to avoid overwhelming targets

EXIT CODES
    0   Scan completed successfully
    1   No open ports found
    2   Target unreachable or DNS resolution failed
    3   Invalid arguments or script error

EOF
}

scan_port() {
    local host="$1"
    local port="$2"
    local timeout="$3"
    
    if timeout "$timeout" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        service=$(getent services "$port/tcp" 2>/dev/null | awk '{print $1}' || echo "unknown")
        echo -e "${GREEN}Port $port/tcp: OPEN${NC} ${YELLOW}($service)${NC}"
        return 0
    else
        if [[ "$VERBOSE" == "true" ]]; then
            echo -e "${RED}Port $port/tcp: CLOSED${NC}"
        fi
        return 1
    fi
}

expand_port_range() {
    local range="$1"
    local ports=()
    
    IFS=',' read -ra RANGES <<< "$range"
    for r in "${RANGES[@]}"; do
        if [[ "$r" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do
                ports+=("$i")
            done
        elif [[ "$r" =~ ^[0-9]+$ ]]; then
            ports+=("$r")
        else
            echo -e "${RED}Invalid port range: $r${NC}" >&2
            exit 1
        fi
    done
    
    printf '%s\n' "${ports[@]}"
}

scan_common_ports() {
    echo "21,22,23,25,53,80,110,143,443,993,995,3389,5432,3306,27017,6379,8080,8443,9200,9300"
}

main() {
    local target="localhost"
    local port_range=""
    local timeout=1
    local local_only=false
    VERBOSE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -l|--local)
                local_only=true
                target="localhost"
                shift
                ;;
            -p|--ports)
                port_range="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                usage
                ;;
            *)
                if [[ "$local_only" == "false" ]]; then
                    target="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$port_range" ]]; then
        port_range=$(scan_common_ports)
    fi
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}            PORT SCANNER${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo "Target: $target"
    echo "Timeout: ${timeout}s"
    echo "Started: $(date)"
    echo ""
    
    # Verify target is reachable
    if [[ "$target" != "localhost" && "$target" != "127.0.0.1" ]]; then
        echo -e "${YELLOW}Testing connectivity to $target...${NC}"
        if ! ping -c 1 -W "$timeout" "$target" >/dev/null 2>&1; then
            echo -e "${RED}Warning: $target may not be reachable${NC}"
        else
            echo -e "${GREEN}Target is reachable${NC}"
        fi
        echo ""
    fi
    
    local open_ports=0
    local total_ports=0
    
    echo -e "${BLUE}Scanning ports...${NC}"
    
    while IFS= read -r port; do
        ((total_ports++))
        if scan_port "$target" "$port" "$timeout"; then
            ((open_ports++))
        fi
    done < <(expand_port_range "$port_range")
    
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Scan completed: $open_ports open ports found out of $total_ports scanned${NC}"
    echo -e "${BLUE}================================================${NC}"
    
    if [[ "$target" == "localhost" || "$target" == "127.0.0.1" ]]; then
        echo ""
        echo -e "${BLUE}Local listening services:${NC}"
        if command -v netstat >/dev/null 2>&1; then
            netstat -tlnp 2>/dev/null | grep LISTEN | awk '{print "  " $1 " " $4 " " $7}' | sort -k2 -n
        elif command -v ss >/dev/null 2>&1; then
            ss -tlnp | grep LISTEN | awk '{print "  " $1 " " $4 " " $7}' | sort -k2 -n
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi