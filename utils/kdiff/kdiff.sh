#!/bin/bash

# kdiff - Kubernetes cluster comparison tool
# Usage: kdiff <cluster1> <cluster2> [command]
#        kdiff deployment (uses configured clusters)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="./kdiff_config"

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
source "$SCRIPT_DIR/lib/deployment.sh"
source "$SCRIPT_DIR/lib/serviceaccount.sh"
source "$SCRIPT_DIR/lib/emissary.sh"
source "$SCRIPT_DIR/lib/contour.sh"
source "$SCRIPT_DIR/lib/mirror.sh"

# Utility functions
print_usage() {
    cat << EOF
kdiff - Kubernetes Cluster Comparison Tool

Usage:
    kdiff <frontend-cluster> <backend-cluster>  # Configure clusters
    kdiff deployment                            # Compare deployments
    kdiff sa                                    # Compare ServiceAccounts with IAM roles
    kdiff help                                  # Show this help

Commands:
    deployment    Compare deployments between configured clusters
    sa            Compare ServiceAccounts with AWS IAM roles
    emissary      Compare Emissary Mappings (name/host/prefix)
    contour       Compare Contour HTTPProxies (name/fqdn)
    mirror        Analyze service mirror setup between clusters
    mirror create [service-name]  Create mirror services in backend cluster

Examples:
    kdiff frontend-prod backend-prod    # Set clusters
    kdiff deployment                    # Compare deployments
    kdiff sa                            # Compare ServiceAccounts with IAM roles
    kdiff emissary                      # Compare Emissary Mappings
    kdiff contour                       # Compare Contour HTTPProxies
    kdiff mirror                        # Analyze mirror services
    kdiff mirror create                 # Create all missing mirror services
    kdiff mirror create ohouse-id-gen   # Create mirror only for specific service
EOF
}

# Main function
main() {
    case "${1:-}" in
        "help"|"-h"|"--help")
            print_usage
            ;;
        "deployment")
            compare_deployments
            ;;
        "sa"|"serviceaccount")
            compare_serviceaccounts
            ;;
        "emissary"|"mapping")
            compare_emissary
            ;;
        "contour"|"httpproxy")
            compare_contour
            ;;
        "mirror"|"all")
            if [[ "${2:-}" == "create" ]]; then
                if [[ -n "${3:-}" ]]; then
                    create_mirror "$3"
                else
                    create_mirror
                fi
            else
                compare_mirror
            fi
            ;;
        "")
            if load_cluster_config; then
                echo -e "${GREEN}Current configuration:${NC}"
                echo "Frontend: $FRONTEND_CLUSTER"
                echo "Backend:  $BACKEND_CLUSTER"
                echo
                echo "Available commands: deployment, sa, emissary, contour, mirror, mirror create"
                echo "Use 'kdiff help' for more information"
            else
                prompt_cluster_setup
            fi
            ;;
        *)
            # Check if two arguments provided (cluster configuration)
            if [[ -n "${2:-}" ]]; then
                local frontend_cluster="$1"
                local backend_cluster="$2"
                
                # Validate both clusters
                if validate_cluster_context "$frontend_cluster" && validate_cluster_context "$backend_cluster"; then
                    save_cluster_config "$frontend_cluster" "$backend_cluster"
                    echo -e "${GREEN}✓ Clusters configured successfully${NC}"
                    echo "Frontend: $frontend_cluster"
                    echo "Backend:  $backend_cluster"
                    echo
                    echo "Now you can use: kdiff deployment, kdiff sa, kdiff emissary, kdiff contour, kdiff mirror, kdiff mirror create"
                else
                    echo -e "${RED}✗ One or both cluster contexts not found${NC}"
                    echo "Available contexts:"
                    kubectl config get-contexts
                    exit 1
                fi
            else
                echo -e "${RED}✗ Unknown command: $1${NC}"
                echo
                print_usage
                exit 1
            fi
            ;;
    esac
}

main "$@"