#!/bin/bash

# lib/deployment.sh - Deployment and Rollout comparison functions

compare_deployments() {
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    echo -e "${BLUE}Comparing deployments and rollouts between clusters...${NC}"
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    echo "Fetching deployments..."
    
    local frontend_deployments=$(kubectl --context="$FRONTEND_CLUSTER" get deployments -A --no-headers 2>/dev/null | awk '{print $1":"$2}' | sort)
    local backend_deployments=$(kubectl --context="$BACKEND_CLUSTER" get deployments -A --no-headers 2>/dev/null | awk '{print $1":"$2}' | sort)
    
    echo "Fetching rollouts..."
    
    local frontend_rollouts=$(kubectl --context="$FRONTEND_CLUSTER" get rollouts -A --no-headers 2>/dev/null | awk '{print $1":"$2}' | sort)
    local backend_rollouts=$(kubectl --context="$BACKEND_CLUSTER" get rollouts -A --no-headers 2>/dev/null | awk '{print $1":"$2}' | sort)
    
    
    local has_frontend_data=false
    local has_backend_data=false
    
    if [[ -n "$frontend_deployments" || -n "$frontend_rollouts" ]]; then
        has_frontend_data=true
    fi
    
    if [[ -n "$backend_deployments" || -n "$backend_rollouts" ]]; then
        has_backend_data=true
    fi
    
    if [[ "$has_frontend_data" == false ]]; then
        echo -e "${RED}✗ No deployments or rollouts found in frontend cluster or connection failed${NC}"
        return 1
    fi
    
    if [[ "$has_backend_data" == false ]]; then
        echo -e "${RED}✗ No deployments or rollouts found in backend cluster or connection failed${NC}"
        return 1
    fi
    
    if [[ -n "$frontend_deployments" || -n "$backend_deployments" ]]; then
        compare_resource_type "Deployments" "$frontend_deployments" "$backend_deployments"
    fi
    
    if [[ -n "$frontend_rollouts" || -n "$backend_rollouts" ]]; then
        compare_resource_type "Rollouts" "$frontend_rollouts" "$backend_rollouts"
    fi
    
    
    echo -e "${BLUE}📊 Overall Summary:${NC}"
    
    local frontend_deploy_count=$(echo "$frontend_deployments" | grep -c '^' 2>/dev/null || echo "0")
    local backend_deploy_count=$(echo "$backend_deployments" | grep -c '^' 2>/dev/null || echo "0")
    local frontend_rollout_count=$(echo "$frontend_rollouts" | grep -c '^' 2>/dev/null || echo "0")
    local backend_rollout_count=$(echo "$backend_rollouts" | grep -c '^' 2>/dev/null || echo "0")
    
    [[ "$frontend_deploy_count" -eq 0 ]] && frontend_deploy_count=0
    [[ "$backend_deploy_count" -eq 0 ]] && backend_deploy_count=0
    [[ "$frontend_rollout_count" -eq 0 ]] && frontend_rollout_count=0
    [[ "$backend_rollout_count" -eq 0 ]] && backend_rollout_count=0
    
    echo "  Frontend: $frontend_deploy_count deployments, $frontend_rollout_count rollouts"
    echo "  Backend:  $backend_deploy_count deployments, $backend_rollout_count rollouts"
}


compare_resource_type() {
    local resource_type="$1"
    local frontend_resources="$2"
    local backend_resources="$3"
    
    
    if [[ -z "$frontend_resources" && -z "$backend_resources" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}=== $resource_type Comparison ===${NC}"
    
    
    local temp_frontend=$(mktemp)
    local temp_backend=$(mktemp)
    
    
    if [[ -n "$frontend_resources" ]]; then
        echo "$frontend_resources" > "$temp_frontend"
    else
        touch "$temp_frontend"
    fi
    
    if [[ -n "$backend_resources" ]]; then
        echo "$backend_resources" > "$temp_backend"
    else
        touch "$temp_backend"
    fi
    
    
    local frontend_only=$(comm -23 "$temp_frontend" "$temp_backend")
    local frontend_count=$(echo "$frontend_only" | grep -c '^' 2>/dev/null || echo "0")
    
    
    if [[ -z "$frontend_only" ]]; then
        frontend_count=0
    fi
    
    if [[ -n "$frontend_only" && "$frontend_count" -gt 0 ]]; then
        local resource_lower=$(echo "$resource_type" | tr '[:upper:]' '[:lower:]')
        echo -e "${RED}🚨 Missing in Backend cluster (${frontend_count} ${resource_lower}):${NC}"
        echo "$frontend_only" | while read line; do
            [[ -n "$line" ]] && echo "  - $line"
        done
        echo
    else
        local resource_lower=$(echo "$resource_type" | tr '[:upper:]' '[:lower:]')
        echo -e "${GREEN}✅ All frontend ${resource_lower} exist in backend cluster${NC}"
        echo
    fi
    
    
    local backend_only=$(comm -13 "$temp_frontend" "$temp_backend")
    local backend_count=$(echo "$backend_only" | grep -c '^' 2>/dev/null || echo "0")
    
    
    if [[ -z "$backend_only" ]]; then
        backend_count=0
    fi
    
    if [[ -n "$backend_only" && "$backend_count" -gt 0 ]]; then
        local resource_lower=$(echo "$resource_type" | tr '[:upper:]' '[:lower:]')
        echo -e "${YELLOW}ℹ️  Additional in Backend cluster (${backend_count} ${resource_lower}):${NC}"
        echo "$backend_only" | while read line; do
            [[ -n "$line" ]] && echo "  - $line"
        done
        echo
    fi
    
    
    local total_frontend=$(echo "$frontend_resources" | grep -c '^' 2>/dev/null || echo "0")
    local total_backend=$(echo "$backend_resources" | grep -c '^' 2>/dev/null || echo "0")
    local common_count=$((total_frontend - frontend_count))
    
    [[ "$total_frontend" -eq 0 ]] && total_frontend=0
    [[ "$total_backend" -eq 0 ]] && total_backend=0
    [[ $common_count -lt 0 ]] && common_count=0
    
    echo -e "${CYAN}📋 $resource_type Summary:${NC}"
    echo "  Frontend total: $total_frontend"
    echo "  Backend total:  $total_backend"  
    echo "  Common:         $common_count"
    echo "  Missing in backend: $frontend_count"
    echo "  Extra in backend:   $backend_count"
    echo
    
    
    rm -f "$temp_frontend" "$temp_backend"
}


compare_rollouts() {
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    echo -e "${BLUE}Comparing rollouts between clusters...${NC}"
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    
    echo "Fetching rollouts..."
    
    local frontend_rollouts=$(kubectl --context="$FRONTEND_CLUSTER" get rollouts -A --no-headers 2>/dev/null | awk '{print $1":"$2}' | sort)
    local backend_rollouts=$(kubectl --context="$BACKEND_CLUSTER" get rollouts -A --no-headers 2>/dev/null | awk '{print $1":"$2}' | sort)
    
    
    if [[ -z "$frontend_rollouts" && -z "$backend_rollouts" ]]; then
        echo -e "${YELLOW}ℹ️  No rollouts found in either cluster${NC}"
        return 0
    fi
    
    compare_resource_type "Rollouts" "$frontend_rollouts" "$backend_rollouts"
}