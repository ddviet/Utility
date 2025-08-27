#!/usr/bin/env bash
# get_os_info.sh
# Purpose:
#   - Detect Linux distribution name and version safely.
#   - Supports modern distros (/etc/os-release) and legacy ones (lsb-release, redhat-release, debian_version).
#
# Notes:
#   - Exit non-zero when OS cannot be detected.
#   - Defaults to short output "<NAME> <VERSION>"; use --full to print the whole file content.
#
# Maintainer: ddviet
SCRIPT_VERSION="1.0.0"

set -euo pipefail

print_usage() {
  cat <<'EOF'
get_os_info.sh — Detect Linux distribution (modern & legacy)

USAGE
  get_os_info.sh [--full] [--version] [-h|--help]

OPTIONS
  --full        Print full content from the OS identification file
                (e.g., /etc/os-release or a legacy fallback)
  --version     Print script version
  -h, --help    Show this help

OUTPUT
  Default (short): "<NAME> <VERSION>"
  With --full   : raw content of the detection file, e.g.:
                  /etc/os-release, /etc/lsb-release, /etc/redhat-release,
                  or "Debian <version>" from /etc/debian_version

EXAMPLES (run directly from GitHub)
  # Using curl (short)
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/get_os_info.sh)"

  # Using curl (FULL output) — note the '--' to pass args to the script:
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/get_os_info.sh)" -- --full

  # Using wget (short)
  bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/get_os_info.sh)"

  # Using wget (FULL output)
  bash -c "$(wget -qO- https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/get_os_info.sh)" -- --full

RECOMMENDED (download, review, then run)
  curl -fsSL -o /tmp/get_os_info.sh https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/get_os_info.sh
  chmod +x /tmp/get_os_info.sh
  /tmp/get_os_info.sh            # short
  /tmp/get_os_info.sh --full     # full

PIN TO A COMMIT (safer; avoids unexpected changes on master)
  RAW="https://raw.githubusercontent.com/ddviet/Utility/<commit-hash>/Linux/get_os_info.sh"
  curl -fsSL -o /tmp/get_os_info.sh "$RAW"
  sha256sum /tmp/get_os_info.sh   # compare with a published checksum if you maintain one
  chmod +x /tmp/get_os_info.sh
  /tmp/get_os_info.sh --full

INSTALL AS A COMMAND (system-wide)
  sudo curl -fsSL -o /usr/local/bin/get_os_info https://raw.githubusercontent.com/ddviet/Utility/refs/heads/master/Linux/get_os_info.sh
  sudo chmod +x /usr/local/bin/get_os_info
  get_os_info
  get_os_info --full

PIPE SAFETY TIPS
  - Prefer download→review→checksum→execute over curl|bash for untrusted sources.
  - Always use HTTPS (raw.githubusercontent.com uses HTTPS by default).
  - Pin to a commit hash when you need deterministic behavior.

EXIT CODES
  0  Success
  1  OS could not be detected
  2  Invalid argument

EOF
}

print_short_from_os_release() {
  # shellcheck disable=SC1091
  . /etc/os-release
  printf "%s %s\n" "${NAME:-Unknown}" "${VERSION:-Unknown}"
}

print_short_from_lsb_release() {
  # shellcheck disable=SC1091
  . /etc/lsb-release
  printf "%s %s\n" "${DISTRIB_ID:-Unknown}" "${DISTRIB_RELEASE:-Unknown}"
}

print_full=0

# --- Parse arguments ---
while (( "$#" )); do
  case "${1:-}" in
    --full)
      print_full=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --version)
      echo "get_os_info.sh v${SCRIPT_VERSION}"
      exit 0
      ;;
    *)
      echo "Invalid argument: $1" >&2
      echo "Use -h or --help to see usage." >&2
      exit 2
      ;;
  esac
done

# --- Main logic ---
if [[ -f /etc/os-release ]]; then
  if (( print_full )); then
    cat /etc/os-release
  else
    print_short_from_os_release
  fi
elif [[ -f /etc/lsb-release ]]; then
  if (( print_full )); then
    cat /etc/lsb-release
  else
    print_short_from_lsb_release
  fi
elif [[ -f /etc/redhat-release ]]; then
  # CentOS/RHEL legacy
  cat /etc/redhat-release
elif [[ -f /etc/debian_version ]]; then
  # Very old Debian
  echo "Debian $(cat /etc/debian_version)"
else
  echo "OS could not be detected"
  exit 1
fi
