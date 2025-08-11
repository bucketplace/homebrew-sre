#!/bin/bash

# akamaistg - Akamai staging test utility
# Usage: akamaistg [command]
#        akamaistg test <host> [path]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="./akamaistg_config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Load library modules
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/testall.sh"

print_usage() {
    cat << EOF
akamaistg - Akamai Staging Test Utility

Usage:
    akamaistg help                                    Show this help
    akamaistg test <url>|<host> [path] [stg|prod]     Test request. Mode via trailing param or env (default: stg)
    akamaistg testall [stg|prod] [targets-yaml]       Run tests for all targets in YAML (mode as first param)

Environment:
    AKAMAISTG_ENV            'staging' (default) or 'prod'. Controls test mode for 'test' and 'testall'.
                             CLI param [stg|prod] takes precedence over this env.
    AKAMAISTG_RESOLVE        staging mode: required or auto-set. prod mode: optional.
                             Format: host:443:IP (passed to curl --resolve)
    AKAMAISTG_STAGING_SUFFIX test: if AKAMAISTG_RESOLVE is not set, suffix used to resolve staging IPs
                             e.g. "edgesuite-staging.net" (default heuristic used if unset)
    AKAMAISTG_STAGING_FQDN   test: if AKAMAISTG_RESOLVE is not set, template FQDN for staging
                             supports {host} placeholder, e.g. "{host}.edgesuite-staging.net"
    AKAMAISTG_TARGETS_YAML   testall: optional YAML file. Defaults to ./akamaistg_targets.yaml

Examples:
    # staging (default)
    AKAMAISTG_STAGING_FQDN='{host}.edgesuite-staging.net' \
      akamaistg test https://www.example.com/health

    # production (via trailing param or env)
    akamaistg test https://www.example.com/health prod
    AKAMAISTG_ENV=prod akamaistg test https://www.example.com/health

    # test all (staging)
    akamaistg testall                  # uses ./akamaistg_targets
    akamaistg testall ./my_targets.txt # specify file
EOF
}

main() {
    case "${1:-}" in
        "help"|"-h"|"--help")
            print_usage
            ;;
        "test")
            shift
            run_test "$@"
            ;;
        "testall")
            shift
            run_test_all "$@"
            ;;
        "")
            print_usage
            ;;
        *)
            echo -e "${RED}✗ Unknown command: $1${NC}" >&2
            echo >&2
            print_usage
            exit 1
            ;;
    esac
}

main "$@"


