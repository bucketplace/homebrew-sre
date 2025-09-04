#!/bin/bash

SCRIPT_NAME="akamai-staging"
HOSTS_FILE="/etc/hosts"

show_help() {
    echo "Usage: $0 <hostname|reset>"
    echo "export ROOT_PASSWORD=<password> to use sudo"
    echo "Examples:"
    echo ""
    echo "  $0 <property on akamai>    - Add staging IP for <property on akamai> (e.g. a-s ohouse.ai)"
    echo "  $0 reset                   - Remove all custom entries, keep system defaults"
    echo ""
    echo "This script manages Akamai staging IP mappings in /etc/hosts"
}

error_exit() {
    echo "Error: $1" >&2
    exit 1
}

success_msg() {
    echo "✓ $1"
}

info_msg() {
    echo "→ $1"
}

reset_hosts() {
    info_msg "Resetting /etc/hosts to system defaults..."
    
    cat > "$HOSTS_FILE" << 'EOF'
##
# Host Database
#
# localhost is used to configure the loopback interface
# when the system is booting.  Do not change this entry.
##
127.0.0.1        localhost
255.255.255.255  broadcasthost
::1              localhost
EOF

    if [ $? -eq 0 ]; then
        success_msg "Successfully reset $HOSTS_FILE to system defaults"
        echo ""
        echo "Current hosts file:"
        cat "$HOSTS_FILE"
        echo ""
        echo "✓ Reset completed successfully!"
    else
        error_exit "Failed to reset hosts file"
    fi
}

if [ $# -ne 1 ]; then
    show_help
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    if [ -n "$ROOT_PASSWORD" ]; then
        echo "Root privileges required. Executing with sudo..."
        echo "$ROOT_PASSWORD" | sudo -S "$0" "$@"
        exit $?
    else
        echo "Root privileges required. Executing with sudo..."
        exec sudo "$0" "$@"
    fi
fi

if [ "$1" = "reset" ]; then
    reset_hosts
    exit 0
fi

HOSTNAME="$1"
if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    error_exit "Invalid hostname format: $HOSTNAME"
fi

if ! command -v dig &> /dev/null; then
    error_exit "dig command not found. Please install dnsutils (Ubuntu/Debian) or bind-utils (RHEL/CentOS)"
fi

info_msg "Looking up A record for ${HOSTNAME}.edgesuite-staging.net..."

STAGING_DOMAIN="${HOSTNAME}.edgesuite-staging.net"
DIG_OUTPUT=$(dig +short "$STAGING_DOMAIN" A)

if [ -z "$DIG_OUTPUT" ]; then
    error_exit "No DNS records found for $STAGING_DOMAIN"
fi

info_msg "DNS lookup result:"
echo "$DIG_OUTPUT" | sed 's/^/  /'

A_RECORD=$(echo "$DIG_OUTPUT" | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -n1)

if [ -z "$A_RECORD" ]; then
    error_exit "No valid IP address found in DNS response"
fi

success_msg "Found A record: $A_RECORD"

info_msg "Removing existing entries for $HOSTNAME..."
if grep -q "[[:space:]]$HOSTNAME[[:space:]]*$" "$HOSTS_FILE"; then
    TEMP_FILE=$(mktemp)
    if ! grep -v "[[:space:]]$HOSTNAME[[:space:]]*$" "$HOSTS_FILE" > "$TEMP_FILE"; then
        rm -f "$TEMP_FILE"
        error_exit "Failed to remove existing entries"
    fi
    if ! mv "$TEMP_FILE" "$HOSTS_FILE"; then
        error_exit "Failed to update hosts file"
    fi
    success_msg "Removed existing entries for $HOSTNAME"
fi

info_msg "Adding new entry: $A_RECORD $HOSTNAME"
ENTRY="$A_RECORD $HOSTNAME"

if ! echo "$ENTRY" >> "$HOSTS_FILE"; then
    error_exit "Failed to add entry to hosts file"
fi

success_msg "Successfully added entry to $HOSTS_FILE"

info_msg "Verifying entry..."
if grep -q "$A_RECORD.*$HOSTNAME" "$HOSTS_FILE"; then
    success_msg "Entry verified in hosts file"
    echo ""
    echo "Current entry:"
    grep "$A_RECORD.*$HOSTNAME" "$HOSTS_FILE"
else
    error_exit "Failed to verify entry in hosts file"
fi

echo ""
echo "✓ Operation completed successfully!"
echo "  Hostname: $HOSTNAME"
echo "  IP Address: $A_RECORD"
echo ""