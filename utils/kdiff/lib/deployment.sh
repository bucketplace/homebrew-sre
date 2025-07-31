#!/bin/bash

# lib/deployment.sh - Deployment comparison functions

compare_deployments() {
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    echo -e "${BLUE}Comparing deployments between clusters...${NC}"
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    # Get deployments from both clusters (faster, no detailed info)
    echo "Fetching deployments..."
    
    local frontend_deployments=$(kubectl --context="$FRONTEND_CLUSTER" get deployments -A --no-headers 2>/dev/null | awk '{print $1":"$2}' | sort)
    local backend_deployments=$(kubectl --context="$BACKEND_CLUSTER" get deployments -A --no-headers 2>/dev/null | awk '{print $1":"$2}' | sort)
    
    if [[ -z "$frontend_deployments" ]]; then
        echo -e "${RED}✗ No deployments found in frontend cluster or connection failed${NC}"
        return 1
    fi
    
    if [[ -z "$backend_deployments" ]]; then
        echo -e "${RED}✗ No deployments found in backend cluster or connection failed${NC}"
        return 1
    fi
    
    # Create temporary files for comparison
    local temp_frontend=$(mktemp)
    local temp_backend=$(mktemp)
    
    echo "$frontend_deployments" > "$temp_frontend"
    echo "$backend_deployments" > "$temp_backend"
    
    # Show results - Focus on differences
    echo -e "${YELLOW}=== Deployment Comparison Results ===${NC}"
    echo
    
    # Only in frontend (핵심!)
    local frontend_only=$(comm -23 "$temp_frontend" "$temp_backend")
    local frontend_count=$(echo "$frontend_only" | grep -c '^' 2>/dev/null || echo "0")
    
    if [[ -n "$frontend_only" && "$frontend_count" -gt 0 ]]; then
        echo -e "${RED}🚨 Missing in Backend cluster (${frontend_count} deployments):${NC}"
        echo "$frontend_only" | while read line; do
            [[ -n "$line" ]] && echo "  - $line"
        done
        echo
    else
        echo -e "${GREEN}✅ All frontend deployments exist in backend cluster${NC}"
        echo
    fi
    
    # Only in backend (참고용)
    local backend_only=$(comm -13 "$temp_frontend" "$temp_backend")
    local backend_count=$(echo "$backend_only" | grep -c '^' 2>/dev/null || echo "0")
    
    if [[ -n "$backend_only" && "$backend_count" -gt 0 ]]; then
        echo -e "${YELLOW}ℹ️  Additional in Backend cluster (${backend_count} deployments):${NC}"
        echo "$backend_only" | while read line; do
            [[ -n "$line" ]] && echo "  - $line"
        done
        echo
    fi
    
    # Summary
    local total_frontend=$(echo "$frontend_deployments" | grep -c '^')
    local total_backend=$(echo "$backend_deployments" | grep -c '^')
    local common_count=$((total_frontend - frontend_count))
    
    echo -e "${BLUE}📊 Summary:${NC}"
    echo "  Frontend total: $total_frontend"
    echo "  Backend total:  $total_backend"
    echo "  Common:         $common_count"
    echo "  Missing in backend: $frontend_count"
    echo "  Extra in backend:   $backend_count"
    
    # Cleanup
    rm -f "$temp_frontend" "$temp_backend"
}