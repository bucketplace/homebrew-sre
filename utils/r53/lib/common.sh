#!/bin/bash

# 현재 작업 디렉토리 기준으로 temp 디렉토리 설정
TEMP_DIR="./temp"

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

configure_r53() {
    if [[ -n "${1:-}" && -n "${2:-}" ]]; then
        local hosted_zone_id="$1"
        local profile="$2"
        
        check_dependencies
        
        if ! validate_profile "$profile"; then
            echo -e "${RED}✗ AWS profile '$profile' not found${NC}"
            echo "Available profiles:"
            aws configure list-profiles 2>/dev/null || echo "No profiles configured"
            exit 1
        fi
        
        if ! validate_hosted_zone "$hosted_zone_id" "$profile"; then
            echo -e "${RED}✗ Hosted zone '$hosted_zone_id' not accessible with profile '$profile'${NC}"
            echo "Please check the hosted zone ID and AWS permissions"
            exit 1
        fi
        
        save_config "$hosted_zone_id" "$profile"
        
        echo -e "${GREEN}✓ Configuration saved successfully${NC}"
        echo "Hosted Zone: $hosted_zone_id"
        echo "AWS Profile: $profile"
        echo ""
        echo "Now you can use: r53 weight, r53 policy"
    else
        echo -e "${RED}✗ Usage: r53 config <hosted-zone-id> <aws-profile>${NC}"
        echo ""
        echo "Examples:"
        echo "  r53 config Z055328915GXZSE19W5LF ohouse-dev"
        echo "  r53 config Z1D633PJN98FT9 ohouse-prod"
        exit 1
    fi
}

cleanup() {
    printf "\033[?25h"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT