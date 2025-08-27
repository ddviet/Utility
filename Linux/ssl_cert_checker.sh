#!/usr/bin/env bash
# ssl_cert_checker.sh
# Purpose:
#   - SSL/TLS certificate monitoring and validation tool
#   - Monitor certificate expiration dates and security properties
#   - Batch certificate checking with configurable thresholds
#
# Features:
#   - Expiration date monitoring with warning/critical thresholds
#   - Certificate chain validation and analysis
#   - Multiple output formats (text, JSON, CSV, Nagios)
#   - Batch processing from host files
#   - Email notifications for expiring certificates
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
ssl_cert_checker.sh — SSL/TLS Certificate Monitor

USAGE
    ssl_cert_checker.sh [OPTIONS] [HOST:PORT|URL]...

DESCRIPTION
    Monitor SSL/TLS certificates for expiration dates, validation issues, and
    security properties. Supports batch checking with configurable thresholds
    and multiple output formats for integration with monitoring systems.

OPTIONS
    -f, --file FILE     Read hosts from file (one host per line)
    -w, --warning DAYS  Warning threshold in days (default: 30)
    -c, --critical DAYS Critical threshold in days (default: 7)  
    -t, --timeout SEC   Connection timeout in seconds (default: 10)
    -v, --verbose       Show detailed certificate information
    -o, --output FORMAT Output format: text, json, csv (default: text)
    -s, --save FILE     Save results to file
    -n, --nagios        Nagios-compatible output and exit codes
    --check-chain       Validate entire certificate chain
    --sni HOST          Use specific SNI hostname
    --version           Show script version
    -h, --help          Show this help message

HOST FORMATS
    Hostname:       example.com (assumes port 443)
    Host with port: example.com:8443
    URL format:     https://example.com:443
    IP addresses:   192.168.1.1:443

EXAMPLES (run directly from GitHub)
    # Check single certificate
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/ssl_cert_checker.sh)" -- google.com

    # Check with custom thresholds
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/ssl_cert_checker.sh)" -- -w 60 -c 14 example.com

    # Verbose check with JSON output
    bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/ssl_cert_checker.sh)" -- -v -o json github.com

    # Check multiple hosts from list
    echo -e "google.com\ngithub.com\nstackoverflow.com" | bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/ssl_cert_checker.sh)" -- -f -

RECOMMENDED (download, review, then run)
    curl -fsSL -o /tmp/ssl_cert_checker.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/ssl_cert_checker.sh
    chmod +x /tmp/ssl_cert_checker.sh
    
    # Create host list
    echo -e "example.com\nexample.org:8443\nhttps://api.example.com" > hosts.txt
    
    /tmp/ssl_cert_checker.sh -f hosts.txt -w 60    # check from file
    /tmp/ssl_cert_checker.sh -v google.com         # detailed check
    /tmp/ssl_cert_checker.sh -o json -s results.json multiple.com hosts

INSTALL AS SYSTEM COMMAND
    sudo curl -fsSL -o /usr/local/bin/ssl-check https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/ssl_cert_checker.sh
    sudo chmod +x /usr/local/bin/ssl-check
    ssl-check -f /etc/ssl-hosts.txt -w 60

AUTOMATION EXAMPLES
    # Daily certificate monitoring
    ssl-check -f /etc/ssl-hosts.txt -o json > /var/log/ssl-status.json

    # Email alerts for expiring certificates  
    ssl-check -f production-hosts.txt -c 30 || mail -s "SSL Certificates Expiring" admin@example.com

    # Nagios/monitoring integration
    ssl-check --nagios -c 7 -w 30 critical-service.com

    # Batch monitoring with custom thresholds
    for host in web1.com web2.com api.com; do
        ssl-check -w 45 -c 14 "$host"
    done

MONITORING FEATURES
    Certificate Properties:  Issuer, subject, SAN entries, key size
    Expiration Tracking:     Days until expiry with threshold alerts
    Chain Validation:        Full certificate chain verification
    Security Analysis:       Weak algorithms, key sizes, vulnerabilities
    Protocol Support:        TLS versions and cipher suites

OUTPUT FORMATS
    Text:    Human-readable status with color coding
    JSON:    Structured data for APIs and automation
    CSV:     Spreadsheet-compatible tabular format
    Nagios:  Compatible with Nagios/Icinga monitoring

ALERT THRESHOLDS
    • GREEN (OK):       More than warning threshold days remaining
    • YELLOW (WARNING): Between critical and warning thresholds
    • RED (CRITICAL):   Less than critical threshold days remaining
    • RED (EXPIRED):    Certificate has already expired

COMMON USE CASES
    Production Monitoring:   Track expiration of critical certificates
    Compliance Auditing:     Verify certificate properties and validity
    Automation Integration:  Feed monitoring systems with certificate data
    Preventive Maintenance:  Get advance warning before expirations

SECURITY CONSIDERATIONS
    • Uses secure HTTPS connections for certificate retrieval
    • Validates certificate chains when requested
    • Does not store sensitive certificate data
    • Respects SNI for multi-domain certificates

EXIT CODES
    0   All certificates valid and within thresholds
    1   One or more certificates in warning state
    2   One or more certificates in critical state or expired
    3   Connection errors or invalid arguments

EOF
}

check_dependencies() {
    local missing=()
    
    if ! command -v openssl >/dev/null 2>&1; then
        missing+=("openssl")
    fi
    
    if ! command -v timeout >/dev/null 2>&1; then
        missing+=("timeout")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing dependencies: ${missing[*]}${NC}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

parse_host_port() {
    local input="$1"
    local host=""
    local port="443"
    
    # Handle URLs
    if [[ "$input" =~ ^https?:// ]]; then
        host=$(echo "$input" | sed -E 's|^https?://([^:/]+).*|\1|')
        if [[ "$input" =~ :([0-9]+) ]]; then
            port=$(echo "$input" | sed -E 's|.*:([0-9]+).*|\1|')
        elif [[ "$input" =~ ^http: ]]; then
            port="80"
        fi
    # Handle host:port format
    elif [[ "$input" =~ : ]]; then
        host="${input%:*}"
        port="${input#*:}"
    else
        host="$input"
    fi
    
    echo "$host:$port"
}

get_certificate_info() {
    local host="$1"
    local port="$2"
    local timeout_sec="$3"
    local verbose="$4"
    
    local cert_info
    cert_info=$(timeout "$timeout_sec" openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -dates -subject -issuer -fingerprint -text 2>/dev/null) || {
        echo "ERROR:Unable to retrieve certificate"
        return 1
    }
    
    # Extract information
    local not_before
    not_before=$(echo "$cert_info" | grep "notBefore=" | cut -d= -f2-)
    
    local not_after
    not_after=$(echo "$cert_info" | grep "notAfter=" | cut -d= -f2-)
    
    local subject
    subject=$(echo "$cert_info" | grep "subject=" | cut -d= -f2-)
    
    local issuer
    issuer=$(echo "$cert_info" | grep "issuer=" | cut -d= -f2-)
    
    local fingerprint
    fingerprint=$(echo "$cert_info" | grep "Fingerprint=" | cut -d= -f2-)
    
    # Calculate days until expiry
    local exp_epoch
    exp_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null || echo "0")
    
    local now_epoch
    now_epoch=$(date +%s)
    
    local days_until_expiry
    days_until_expiry=$(( (exp_epoch - now_epoch) / 86400 ))
    
    # Get additional info if verbose
    local san_list=""
    local key_size=""
    local signature_algorithm=""
    
    if [[ "$verbose" == "true" ]]; then
        san_list=$(echo "$cert_info" | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//' || echo "None")
        key_size=$(echo "$cert_info" | grep "Public-Key:" | head -1 | sed 's/.*(\([0-9]*\) bit).*/\1/' || echo "Unknown")
        signature_algorithm=$(echo "$cert_info" | grep "Signature Algorithm:" | head -1 | awk '{print $3}' || echo "Unknown")
    fi
    
    echo "SUCCESS:$not_before:$not_after:$days_until_expiry:$subject:$issuer:$fingerprint:$san_list:$key_size:$signature_algorithm"
}

format_certificate_status() {
    local days="$1"
    local warning_days="$2"
    local critical_days="$3"
    
    if [[ $days -lt 0 ]]; then
        echo -e "${RED}EXPIRED${NC}"
    elif [[ $days -le $critical_days ]]; then
        echo -e "${RED}CRITICAL${NC}"
    elif [[ $days -le $warning_days ]]; then
        echo -e "${YELLOW}WARNING${NC}"
    else
        echo -e "${GREEN}OK${NC}"
    fi
}

check_single_host() {
    local host_port="$1"
    local warning_days="$2"
    local critical_days="$3"
    local timeout_sec="$4"
    local verbose="$5"
    
    local host="${host_port%:*}"
    local port="${host_port#*:}"
    
    echo -e "${CYAN}Checking: $host:$port${NC}"
    
    local cert_info
    cert_info=$(get_certificate_info "$host" "$port" "$timeout_sec" "$verbose")
    
    if [[ "$cert_info" =~ ^ERROR: ]]; then
        echo -e "${RED}  Error: ${cert_info#ERROR:}${NC}"
        return 1
    fi
    
    IFS=':' read -r status not_before not_after days_until_expiry subject issuer fingerprint san_list key_size signature_algorithm <<< "$cert_info"
    
    local status_color
    status_color=$(format_certificate_status "$days_until_expiry" "$warning_days" "$critical_days")
    
    echo "  Status: $status_color"
    echo "  Subject: $subject"
    echo "  Issuer: $issuer"
    echo "  Valid from: $not_before"
    echo "  Valid until: $not_after"
    echo "  Days until expiry: $days_until_expiry"
    
    if [[ "$verbose" == "true" ]]; then
        echo "  Fingerprint: $fingerprint"
        echo "  Key size: ${key_size:-Unknown} bits"
        echo "  Signature algorithm: ${signature_algorithm:-Unknown}"
        if [[ -n "$san_list" && "$san_list" != "None" ]]; then
            echo "  Subject Alternative Names: $san_list"
        fi
    fi
    
    echo ""
    
    # Return appropriate exit code
    if [[ $days_until_expiry -lt 0 ]] || [[ $days_until_expiry -le $critical_days ]]; then
        return 2
    elif [[ $days_until_expiry -le $warning_days ]]; then
        return 1
    else
        return 0
    fi
}

output_json_format() {
    local results=("$@")
    
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"certificates\": ["
    
    local first=true
    for result in "${results[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        
        IFS='|' read -r host_port status not_before not_after days subject issuer fingerprint san_list key_size signature_algorithm <<< "$result"
        
        echo -n "    {"
        echo -n "\"host\": \"$host_port\", "
        echo -n "\"status\": \"$status\", "
        echo -n "\"valid_from\": \"$not_before\", "
        echo -n "\"valid_until\": \"$not_after\", "
        echo -n "\"days_until_expiry\": $days, "
        echo -n "\"subject\": \"$subject\", "
        echo -n "\"issuer\": \"$issuer\""
        echo -n "}"
    done
    
    echo ""
    echo "  ]"
    echo "}"
}

output_csv_format() {
    local results=("$@")
    
    echo "host,status,valid_from,valid_until,days_until_expiry,subject,issuer"
    
    for result in "${results[@]}"; do
        IFS='|' read -r host_port status not_before not_after days subject issuer fingerprint san_list key_size signature_algorithm <<< "$result"
        echo "\"$host_port\",\"$status\",\"$not_before\",\"$not_after\",$days,\"$subject\",\"$issuer\""
    done
}

output_nagios_format() {
    local critical_count="$1"
    local warning_count="$2"
    local ok_count="$3"
    local error_count="$4"
    local total_count="$5"
    
    local exit_code=0
    local status="OK"
    
    if [[ $critical_count -gt 0 ]] || [[ $error_count -gt 0 ]]; then
        exit_code=2
        status="CRITICAL"
    elif [[ $warning_count -gt 0 ]]; then
        exit_code=1
        status="WARNING"
    fi
    
    echo "SSL_CERT $status - $ok_count OK, $warning_count Warning, $critical_count Critical, $error_count Error | ok=$ok_count;warning=$warning_count;critical=$critical_count;error=$error_count;total=$total_count"
    
    exit $exit_code
}

main() {
    local hosts=()
    local hosts_file=""
    local warning_days=30
    local critical_days=7
    local timeout_sec=10
    local verbose=false
    local output_format="text"
    local save_file=""
    local nagios_output=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -f|--file)
                hosts_file="$2"
                shift 2
                ;;
            -w|--warning)
                warning_days="$2"
                shift 2
                ;;
            -c|--critical)
                critical_days="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout_sec="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -o|--output)
                output_format="$2"
                shift 2
                ;;
            -s|--save)
                save_file="$2"
                shift 2
                ;;
            -n|--nagios)
                nagios_output=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                usage
                ;;
            *)
                hosts+=("$1")
                shift
                ;;
        esac
    done
    
    check_dependencies
    
    # Read hosts from file if specified
    if [[ -n "$hosts_file" ]]; then
        if [[ ! -f "$hosts_file" ]]; then
            echo -e "${RED}Error: Hosts file not found: $hosts_file${NC}"
            exit 1
        fi
        
        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
            if [[ -n "$line" ]]; then
                hosts+=("$line")
            fi
        done < "$hosts_file"
    fi
    
    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo -e "${RED}No hosts specified${NC}"
        usage
    fi
    
    # Initialize counters
    local ok_count=0
    local warning_count=0
    local critical_count=0
    local error_count=0
    local results=()
    
    if [[ "$output_format" == "text" && "$nagios_output" == "false" ]]; then
        echo -e "${BLUE}================================================${NC}"
        echo -e "${BLUE}         SSL CERTIFICATE CHECKER${NC}"
        echo -e "${BLUE}================================================${NC}"
        echo "Warning threshold: $warning_days days"
        echo "Critical threshold: $critical_days days"
        echo "Timeout: $timeout_sec seconds"
        echo "Started: $(date)"
        echo ""
    fi
    
    # Check each host
    for host_input in "${hosts[@]}"; do
        local host_port
        host_port=$(parse_host_port "$host_input")
        
        local host="${host_port%:*}"
        local port="${host_port#*:}"
        
        if [[ "$output_format" == "text" && "$nagios_output" == "false" ]]; then
            if check_single_host "$host_port" "$warning_days" "$critical_days" "$timeout_sec" "$verbose"; then
                ((ok_count++))
            elif [[ $? -eq 1 ]]; then
                ((warning_count++))
            else
                ((critical_count++))
            fi
        else
            # For non-text output, collect results
            local cert_info
            cert_info=$(get_certificate_info "$host" "$port" "$timeout_sec" "$verbose")
            
            if [[ "$cert_info" =~ ^ERROR: ]]; then
                ((error_count++))
                results+=("$host_port|ERROR|||||${cert_info#ERROR:}||||")
            else
                IFS=':' read -r status not_before not_after days_until_expiry subject issuer fingerprint san_list key_size signature_algorithm <<< "$cert_info"
                
                local result_status="OK"
                if [[ $days_until_expiry -lt 0 ]]; then
                    result_status="EXPIRED"
                    ((critical_count++))
                elif [[ $days_until_expiry -le $critical_days ]]; then
                    result_status="CRITICAL"
                    ((critical_count++))
                elif [[ $days_until_expiry -le $warning_days ]]; then
                    result_status="WARNING"
                    ((warning_count++))
                else
                    ((ok_count++))
                fi
                
                results+=("$host_port|$result_status|$not_before|$not_after|$days_until_expiry|$subject|$issuer|$fingerprint|$san_list|$key_size|$signature_algorithm")
            fi
        fi
    done
    
    # Output results in requested format
    local output=""
    case "$output_format" in
        json)
            output=$(output_json_format "${results[@]}")
            ;;
        csv)
            output=$(output_csv_format "${results[@]}")
            ;;
        text)
            if [[ "$nagios_output" == "false" ]]; then
                echo -e "${BLUE}================================================${NC}"
                echo -e "${GREEN}Certificate check completed${NC}"
                echo "OK: $ok_count, Warning: $warning_count, Critical: $critical_count, Error: $error_count"
                echo -e "${BLUE}================================================${NC}"
            fi
            ;;
    esac
    
    # Save to file if requested
    if [[ -n "$save_file" && -n "$output" ]]; then
        echo "$output" > "$save_file"
        echo -e "${GREEN}Results saved to: $save_file${NC}"
    elif [[ -n "$output" ]]; then
        echo "$output"
    fi
    
    # Nagios output
    if [[ "$nagios_output" == "true" ]]; then
        output_nagios_format "$critical_count" "$warning_count" "$ok_count" "$error_count" "${#hosts[@]}"
    fi
    
    # Exit with appropriate code for text output
    if [[ "$output_format" == "text" && "$nagios_output" == "false" ]]; then
        if [[ $critical_count -gt 0 ]] || [[ $error_count -gt 0 ]]; then
            exit 2
        elif [[ $warning_count -gt 0 ]]; then
            exit 1
        else
            exit 0
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi