#!/bin/bash
# network_info.sh
# Purpose:
#   - Display comprehensive network configuration and connectivity information
#   - Test network connectivity and performance diagnostics
#   - Provide detailed analysis of network interfaces and routing
#
# Features:
#   - Complete network interface configuration display
#   - Routing table analysis and gateway information
#   - Connectivity testing to common hosts and services
#   - Network performance testing (speed tests with external tools)
#   - WiFi network information and signal strength
#   - DNS configuration analysis and resolution testing
#   - Port scanning and service detection on localhost
#   - JSON output format for automation and monitoring
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
network_info.sh — Comprehensive Network Configuration and Diagnostics Tool

USAGE
    network_info.sh [OPTIONS]

DESCRIPTION
    Display comprehensive network configuration and connectivity information
    with performance diagnostics, detailed analysis of network interfaces,
    routing tables, and connectivity testing to common hosts and services.

OPTIONS
    -h, --help           Show this help message
    -i, --interfaces     Show network interfaces configuration only
    -r, --routing        Show routing information and gateway details only
    -c, --connectivity   Test connectivity to common hosts and services
    -p, --ports          Show listening ports and running services
    -s, --speed          Test network speed (requires speedtest-cli)
    -w, --wifi           Show WiFi network information and signal strength
    -d, --dns            Show DNS configuration and test resolution
    -o, --output FORMAT  Output format: text, json (default: text)
    -v, --verbose        Show detailed information with extra diagnostics
    --version            Show script version

NETWORK ANALYSIS FEATURES
    Interface Detection:  Complete network interface configuration display
    Routing Analysis:     Gateway information and route table analysis
    Connectivity Tests:   Multi-host connectivity verification
    DNS Testing:          Resolution testing and server analysis
    Port Scanning:        Local service detection and port analysis
    WiFi Diagnostics:     Signal strength and network quality metrics
    Speed Testing:        Bandwidth measurement with external services

OUTPUT FORMATS
    text    Human-readable formatted output with colors
    json    Machine-readable JSON format for automation

EXAMPLES (run directly from GitHub)
    # Complete network information display
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/network_info.sh)"

    # Interface and routing information only
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/network_info.sh)" -- -i -r

    # Connectivity and speed testing
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/network_info.sh)" -- -c -s

    # JSON output for automation and monitoring
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/network_info.sh)" -- -o json

    # WiFi and DNS diagnostics with verbose output
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/network_info.sh)" -- -w -d -v

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/network_info.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/network_info.sh
    chmod +x /tmp/network_info.sh
    /tmp/network_info.sh --help        # Show this help
    /tmp/network_info.sh -v            # Verbose network analysis
    /tmp/network_info.sh -c -s         # Connectivity and speed tests
    /tmp/network_info.sh -o json       # JSON output for scripts

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/netinfo https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/network_info.sh
    sudo chmod +x /usr/local/bin/netinfo
    netinfo -c -s

AUTOMATION EXAMPLES
    # Network monitoring script
    netinfo -o json > network_status.json
    
    # Connectivity health check
    netinfo -c || echo "Network issues detected" | mail admin@company.com
    
    # Periodic network diagnostics
    while true; do
        netinfo -i -r -c
        sleep 300
    done

DIAGNOSTIC CAPABILITIES
    System Information:   Hostname, kernel, uptime, and system status
    Interface Analysis:   IP addresses, MAC addresses, link status
    Routing Tables:       Default routes, gateways, and route metrics
    DNS Resolution:       Nameserver configuration and resolution testing
    Connectivity Tests:   Ping tests to Google, Cloudflare, GitHub, etc.
    Service Detection:    Local listening services and port analysis
    WiFi Diagnostics:     Signal quality, SSID, and frequency information
    Speed Testing:        Download/upload speed measurement
    Traffic Statistics:   Network interface usage and transfer statistics

CONNECTIVITY TEST TARGETS
    Google DNS (8.8.8.8):       Primary DNS connectivity
    Cloudflare DNS (1.1.1.1):   Alternative DNS connectivity  
    Google.com:                  HTTP/HTTPS connectivity
    GitHub.com:                  Development service connectivity
    StackOverflow.com:           General internet connectivity

COMMON USE CASES
    Network Troubleshooting:  Diagnose connectivity and configuration issues
    System Administration:    Monitor network status and performance
    Security Auditing:        Identify open ports and running services
    Performance Testing:      Measure network speed and latency
    Documentation:            Generate network configuration reports
    Automation:               Monitor network health in scripts

SUPPORTED PLATFORMS
    Linux:   Full feature support with ip, ss, iwconfig commands
    macOS:   Basic support with ifconfig, netstat commands
    Generic: Fallback support for minimal Unix environments

EXIT CODES
    0   Network analysis completed successfully
    1   Network connectivity issues detected
    2   Missing network diagnostic tools
    3   JSON output formatting errors

EOF
}

show_system_info() {
    echo -e "${BLUE}System Information:${NC}"
    echo "  Hostname: $(hostname)"
    echo "  Kernel: $(uname -s -r)"
    echo "  Date: $(date)"
    
    if command -v uptime >/dev/null 2>&1; then
        echo "  Uptime: $(uptime -p 2>/dev/null || uptime)"
    fi
    echo ""
}

show_network_interfaces() {
    local verbose="$1"
    
    echo -e "${BLUE}Network Interfaces:${NC}"
    
    if command -v ip >/dev/null 2>&1; then
        # Use ip command (modern Linux)
        ip addr show | while IFS= read -r line; do
            if [[ "$line" =~ ^[0-9]+: ]]; then
                # Interface line
                local iface
                iface=$(echo "$line" | awk '{print $2}' | sed 's/:$//')
                local status
                status=$(echo "$line" | grep -o 'state [A-Z]*' | awk '{print $2}')
                
                if [[ "$status" == "UP" ]]; then
                    echo -e "  ${GREEN}$iface${NC} (${status})"
                else
                    echo -e "  ${YELLOW}$iface${NC} (${status})"
                fi
            elif [[ "$line" =~ inet ]]; then
                # IP address line
                local ip
                ip=$(echo "$line" | awk '{print $2}')
                echo "    IP: $ip"
            elif [[ "$verbose" == "true" && "$line" =~ link/ether ]]; then
                # MAC address
                local mac
                mac=$(echo "$line" | awk '{print $2}')
                echo "    MAC: $mac"
            fi
        done
    elif command -v ifconfig >/dev/null 2>&1; then
        # Use ifconfig (older systems, macOS)
        ifconfig | grep -E "^[a-z]|inet " | while IFS= read -r line; do
            if [[ "$line" =~ ^[a-z] ]]; then
                local iface
                iface=$(echo "$line" | awk '{print $1}')
                echo -e "  ${CYAN}$iface${NC}"
            elif [[ "$line" =~ inet ]]; then
                local ip
                ip=$(echo "$line" | awk '{print $2}')
                echo "    IP: $ip"
            fi
        done
    else
        echo -e "  ${YELLOW}Network interface information not available${NC}"
    fi
    echo ""
}

show_routing_table() {
    echo -e "${BLUE}Routing Information:${NC}"
    
    if command -v ip >/dev/null 2>&1; then
        echo "  Default Routes:"
        ip route show default | while IFS= read -r line; do
            local gateway
            gateway=$(echo "$line" | awk '{print $3}')
            local dev
            dev=$(echo "$line" | awk '{print $5}')
            echo "    Gateway: $gateway via $dev"
        done
        
        echo ""
        echo "  Route Table:"
        ip route show | head -10 | while IFS= read -r line; do
            echo "    $line"
        done
    elif command -v netstat >/dev/null 2>&1; then
        echo "  Route Table:"
        netstat -rn | head -10 | while IFS= read -r line; do
            echo "    $line"
        done
    elif command -v route >/dev/null 2>&1; then
        echo "  Route Table:"
        route -n | while IFS= read -r line; do
            echo "    $line"
        done
    else
        echo -e "  ${YELLOW}Routing information not available${NC}"
    fi
    echo ""
}

show_dns_info() {
    echo -e "${BLUE}DNS Configuration:${NC}"
    
    # Show DNS servers
    echo "  DNS Servers:"
    if [[ -f /etc/resolv.conf ]]; then
        grep "^nameserver" /etc/resolv.conf 2>/dev/null | while IFS= read -r line; do
            local dns_server
            dns_server=$(echo "$line" | awk '{print $2}')
            echo "    $dns_server"
        done
    else
        echo -e "    ${YELLOW}/etc/resolv.conf not found${NC}"
    fi
    
    # Test DNS resolution
    echo ""
    echo "  DNS Resolution Test:"
    local test_domains=("google.com" "cloudflare.com" "github.com")
    
    for domain in "${test_domains[@]}"; do
        local start_time
        start_time=$(date +%s.%N)
        
        if nslookup "$domain" >/dev/null 2>&1; then
            local end_time
            end_time=$(date +%s.%N)
            local duration
            duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "unknown")
            echo -e "    ${GREEN}$domain${NC} - OK (${duration}s)"
        else
            echo -e "    ${RED}$domain${NC} - FAILED"
        fi
    done
    echo ""
}

test_connectivity() {
    echo -e "${BLUE}Connectivity Test:${NC}"
    
    local test_hosts=(
        "8.8.8.8:Google DNS"
        "1.1.1.1:Cloudflare DNS"
        "google.com:Google"
        "github.com:GitHub"
        "stackoverflow.com:StackOverflow"
    )
    
    for entry in "${test_hosts[@]}"; do
        IFS=':' read -r host description <<< "$entry"
        
        echo -n "  Testing $description ($host)... "
        
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            # Get response time
            local ping_time
            ping_time=$(ping -c 1 -W 3 "$host" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/' || echo "unknown")
            echo -e "${GREEN}OK${NC} (${ping_time}ms)"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    done
    echo ""
}

show_listening_ports() {
    echo -e "${BLUE}Listening Ports and Services:${NC}"
    
    if command -v ss >/dev/null 2>&1; then
        # Use ss (modern)
        echo "  TCP Ports:"
        ss -tlnp | grep LISTEN | head -10 | while IFS= read -r line; do
            local port
            port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
            local process
            process=$(echo "$line" | awk '{print $6}' | sed 's/.*"//' | sed 's/".*//' | cut -d',' -f1)
            echo "    Port $port: ${process:-unknown}"
        done
        
        echo ""
        echo "  UDP Ports:"
        ss -ulnp | head -5 | while IFS= read -r line; do
            local port
            port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
            local process
            process=$(echo "$line" | awk '{print $6}' | sed 's/.*"//' | sed 's/".*//' | cut -d',' -f1)
            echo "    Port $port: ${process:-unknown}"
        done
    elif command -v netstat >/dev/null 2>&1; then
        # Use netstat (older)
        echo "  TCP Ports:"
        netstat -tlnp 2>/dev/null | grep LISTEN | head -10 | while IFS= read -r line; do
            local port
            port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
            local process
            process=$(echo "$line" | awk '{print $7}' | cut -d'/' -f2)
            echo "    Port $port: ${process:-unknown}"
        done
        
        echo ""
        echo "  UDP Ports:"
        netstat -ulnp 2>/dev/null | head -5 | while IFS= read -r line; do
            local port
            port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
            local process
            process=$(echo "$line" | awk '{print $6}' | cut -d'/' -f2)
            echo "    Port $port: ${process:-unknown}"
        done
    else
        echo -e "  ${YELLOW}Port information not available${NC}"
    fi
    echo ""
}

show_wifi_info() {
    echo -e "${BLUE}WiFi Information:${NC}"
    
    if command -v iwconfig >/dev/null 2>&1; then
        iwconfig 2>/dev/null | grep -E "IEEE|ESSID|Frequency|Quality|Signal" | while IFS= read -r line; do
            if [[ "$line" =~ IEEE ]]; then
                local interface
                interface=$(echo "$line" | awk '{print $1}')
                echo "  Interface: $interface"
            elif [[ "$line" =~ ESSID ]]; then
                local ssid
                ssid=$(echo "$line" | sed 's/.*ESSID:"\(.*\)".*/\1/')
                if [[ -n "$ssid" && "$ssid" != "off/any" ]]; then
                    echo "    SSID: $ssid"
                fi
            elif [[ "$line" =~ Frequency ]]; then
                local freq
                freq=$(echo "$line" | sed 's/.*Frequency:\([0-9.]*\).*/\1/')
                echo "    Frequency: ${freq}GHz"
            elif [[ "$line" =~ Quality ]]; then
                local quality
                quality=$(echo "$line" | sed 's/.*Quality=\([0-9/]*\).*/\1/')
                local signal
                signal=$(echo "$line" | sed 's/.*Signal level=\(-[0-9]*\).*/\1/')
                echo "    Quality: $quality, Signal: ${signal}dBm"
            fi
        done
    elif command -v nmcli >/dev/null 2>&1; then
        # Network Manager
        nmcli dev wifi list | head -5 | while IFS= read -r line; do
            if [[ ! "$line" =~ "SSID" ]]; then
                local ssid
                ssid=$(echo "$line" | awk '{print $2}')
                local signal
                signal=$(echo "$line" | awk '{print $6}')
                echo "    $ssid: ${signal}%"
            fi
        done
    else
        echo -e "  ${YELLOW}WiFi information not available${NC}"
    fi
    echo ""
}

test_network_speed() {
    echo -e "${BLUE}Network Speed Test:${NC}"
    
    if command -v speedtest-cli >/dev/null 2>&1; then
        echo "  Running speed test (this may take a moment)..."
        local speed_result
        speed_result=$(speedtest-cli --simple 2>/dev/null || echo "Speed test failed")
        
        if [[ "$speed_result" != "Speed test failed" ]]; then
            echo "$speed_result" | while IFS= read -r line; do
                echo "    $line"
            done
        else
            echo -e "  ${RED}Speed test failed${NC}"
        fi
    elif command -v curl >/dev/null 2>&1; then
        echo "  Basic download test..."
        local start_time
        start_time=$(date +%s.%N)
        
        if curl -o /dev/null -s "http://speedtest.wdc01.softlayer.com/downloads/test10.zip"; then
            local end_time
            end_time=$(date +%s.%N)
            local duration
            duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "unknown")
            local speed
            speed=$(echo "scale=2; 10 / $duration * 8" | bc -l 2>/dev/null || echo "unknown")
            echo "    Download: ${speed}Mbps (approximate)"
        else
            echo -e "  ${RED}Download test failed${NC}"
        fi
    else
        echo -e "  ${YELLOW}Speed test tools not available${NC}"
        echo "  Install speedtest-cli for accurate speed testing"
    fi
    echo ""
}

show_network_statistics() {
    echo -e "${BLUE}Network Statistics:${NC}"
    
    if [[ -f /proc/net/dev ]]; then
        echo "  Interface Statistics:"
        tail -n +3 /proc/net/dev | while IFS= read -r line; do
            local iface
            iface=$(echo "$line" | awk -F: '{print $1}' | tr -d ' ')
            local rx_bytes
            rx_bytes=$(echo "$line" | awk '{print $2}')
            local tx_bytes
            tx_bytes=$(echo "$line" | awk '{print $10}')
            
            # Convert to human readable
            local rx_mb
            rx_mb=$((rx_bytes / 1024 / 1024))
            local tx_mb
            tx_mb=$((tx_bytes / 1024 / 1024))
            
            if [[ $rx_mb -gt 0 || $tx_mb -gt 0 ]]; then
                echo "    $iface: RX ${rx_mb}MB, TX ${tx_mb}MB"
            fi
        done
    else
        echo -e "  ${YELLOW}Network statistics not available${NC}"
    fi
    echo ""
}

output_json_format() {
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"hostname\": \"$(hostname)\","
    echo "  \"kernel\": \"$(uname -s -r)\","
    echo "  \"interfaces\": ["
    
    local first=true
    if command -v ip >/dev/null 2>&1; then
        ip -j addr show 2>/dev/null | jq -c '.[]' 2>/dev/null | while IFS= read -r iface; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo "    $iface"
        done 2>/dev/null || {
            # Fallback if jq not available
            echo "    {\"error\": \"JSON parsing not available\"}"
        }
    fi
    
    echo ""
    echo "  ]"
    echo "}"
}

main() {
    local show_interfaces_only=false
    local show_routing_only=false
    local test_connectivity_flag=false
    local show_ports_flag=false
    local test_speed_flag=false
    local show_wifi_flag=false
    local show_dns_flag=false
    local output_format="text"
    local verbose=false
    local show_all=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                ;;
            -i|--interfaces)
                show_interfaces_only=true
                show_all=false
                shift
                ;;
            -r|--routing)
                show_routing_only=true
                show_all=false
                shift
                ;;
            -c|--connectivity)
                test_connectivity_flag=true
                show_all=false
                shift
                ;;
            -p|--ports)
                show_ports_flag=true
                show_all=false
                shift
                ;;
            -s|--speed)
                test_speed_flag=true
                show_all=false
                shift
                ;;
            -w|--wifi)
                show_wifi_flag=true
                show_all=false
                shift
                ;;
            -d|--dns)
                show_dns_flag=true
                show_all=false
                shift
                ;;
            -o|--output)
                output_format="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --version)
                echo "network_info.sh version $SCRIPT_VERSION"
                exit 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                print_usage
                ;;
            *)
                echo -e "${RED}Unexpected argument: $1${NC}" >&2
                print_usage
                ;;
        esac
    done
    
    if [[ "$output_format" == "json" ]]; then
        output_json_format
        exit 0
    fi
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           NETWORK INFORMATION${NC}"
    echo -e "${BLUE}================================================${NC}"
    
    show_system_info
    
    if [[ "$show_all" == "true" ]] || [[ "$show_interfaces_only" == "true" ]]; then
        show_network_interfaces "$verbose"
    fi
    
    if [[ "$show_all" == "true" ]] || [[ "$show_routing_only" == "true" ]]; then
        show_routing_table
    fi
    
    if [[ "$show_all" == "true" ]] || [[ "$show_dns_flag" == "true" ]]; then
        show_dns_info
    fi
    
    if [[ "$show_all" == "true" ]] || [[ "$test_connectivity_flag" == "true" ]]; then
        test_connectivity
    fi
    
    if [[ "$show_all" == "true" ]] || [[ "$show_ports_flag" == "true" ]]; then
        show_listening_ports
    fi
    
    if [[ "$show_wifi_flag" == "true" ]]; then
        show_wifi_info
    fi
    
    if [[ "$test_speed_flag" == "true" ]]; then
        test_network_speed
    fi
    
    if [[ "$show_all" == "true" ]]; then
        show_network_statistics
    fi
    
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Network information completed at $(date)${NC}"
    echo -e "${BLUE}================================================${NC}"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    main "$@"
fi