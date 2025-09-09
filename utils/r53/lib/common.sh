#!/bin/bash

TEMP_DIR="/tmp/r53_tool"

mkdir -p "$TEMP_DIR"

save_config() {
    local hosted_zone_id="$1"
    local profile="$2"
    
    cat > "$CONFIG_FILE" << EOF
HOSTED_ZONE_ID="$hosted_zone_id"
PROFILE="$profile"
EOF
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

validate_profile() {
    local profile="$1"
    
    if aws configure list-profiles 2>/dev/null | grep -q "^${profile}$"; then
        return 0
    else
        return 1
    fi
}

validate_hosted_zone() {
    local zone_id="$1"
    local profile="$2"
    
    if aws route53 get-hosted-zone --id "$zone_id" --profile "$profile" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_dependencies() {
    local missing_deps=()
    
    if ! command -v aws &> /dev/null; then
        missing_deps+=("AWS CLI")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v tput &> /dev/null; then
        missing_deps+=("tput")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Missing dependencies: ${missing_deps[*]}${NC}"
        exit 1
    fi
}

cleanup() {
    printf "\033[?25h"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT