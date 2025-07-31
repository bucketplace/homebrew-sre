#!/bin/bash

# lib/common.sh - Common functions for kdiff

# Configuration functions
save_cluster_config() {
    local frontend_cluster="$1"
    local backend_cluster="$2"
    
    cat > "$CONFIG_FILE" << EOF
FRONTEND_CLUSTER="$frontend_cluster"
BACKEND_CLUSTER="$backend_cluster"
EOF
    echo -e "${GREEN}✓ Cluster configuration saved${NC}"
}

load_cluster_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

validate_cluster_context() {
    local cluster="$1"
    kubectl config get-contexts "$cluster" &>/dev/null
    return $?
}

prompt_cluster_setup() {
    echo -e "${YELLOW}No cluster configuration found.${NC}"
    echo "Please configure your clusters first:"
    echo
    
    while true; do
        read -p "Enter frontend cluster context name: " frontend_cluster
        if validate_cluster_context "$frontend_cluster"; then
            break
        else
            echo -e "${RED}✗ Context '$frontend_cluster' not found. Please check your kubectl contexts.${NC}"
            kubectl config get-contexts
            echo
        fi
    done
    
    while true; do
        read -p "Enter backend cluster context name: " backend_cluster
        if validate_cluster_context "$backend_cluster"; then
            break
        else
            echo -e "${RED}✗ Context '$backend_cluster' not found. Please check your kubectl contexts.${NC}"
            kubectl config get-contexts
            echo
        fi
    done
    
    save_cluster_config "$frontend_cluster" "$backend_cluster"
}