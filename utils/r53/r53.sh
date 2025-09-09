#!/bin/bash

# r53 - Route 53 management tool
# Usage: r53 <command> [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="./r53_config"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/weight.sh"

print_usage() {
    cat << EOF
r53 - Route 53 Management Tool

Usage:
    r53 weight <hosted-zone-id> <aws-profile>    # Configure and start weight manager
    r53 weight                                   # Use previously configured settings
    r53 help                                     # Show this help

Commands:
    weight    Interactive weight management for weighted routing records

Examples:
    r53 weight Z055328915GXZSE19W5LF ohouse-dev    # Configure and start
    r53 weight                                     # Use saved configuration

Features:
    • Interactive record selection with arrow keys
    • Shows current values (IP addresses, CNAMEs) 
    • Real-time weight changes applied to AWS Route 53
    • Automatic record refresh after changes
    • Continuous workflow for multiple changes
EOF
}

show_config() {
    if load_config; then
        echo -e "${GREEN}Current configuration:${NC}"
        echo "Hosted Zone: $HOSTED_ZONE_ID"
        echo "AWS Profile: $PROFILE"
        echo ""
        echo "Available commands: weight"
        echo "Use 'r53 help' for more information"
    else
        echo -e "${YELLOW}No configuration found${NC}"
        echo "Use 'r53 weight <hosted-zone-id> <aws-profile>' to configure"
    fi
}

main() {
    case "${1:-}" in
        "help"|"-h"|"--help")
            print_usage
            ;;
        "weight")
            manage_weights "${@:2}"
            ;;
        "")
            show_config
            ;;
        *)
            echo -e "${RED}✗ Unknown command: $1${NC}"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

main "$@"