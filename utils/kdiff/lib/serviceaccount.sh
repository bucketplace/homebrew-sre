#!/bin/bash

# lib/serviceaccount.sh - ServiceAccount comparison functions

compare_serviceaccounts() {
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    echo -e "${BLUE}Checking ServiceAccounts with AWS IAM roles for OIDC trust setup...${NC}"
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    # Get ServiceAccounts with IAM roles from both clusters (excluding kube-system)
    echo "Fetching ServiceAccounts with IAM roles (excluding kube-system)..."
    
    local frontend_sa=$(kubectl --context="$FRONTEND_CLUSTER" get serviceaccounts -A -o jsonpath='{range .items[?(@.metadata.annotations.eks\.amazonaws\.com/role-arn)]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}{end}' 2>/dev/null | grep -v "^kube-system" | sort)
    
    local backend_sa=$(kubectl --context="$BACKEND_CLUSTER" get serviceaccounts -A -o jsonpath='{range .items[?(@.metadata.annotations.eks\.amazonaws\.com/role-arn)]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}{end}' 2>/dev/null | grep -v "^kube-system" | sort)
    
    # Show results
    echo -e "${YELLOW}=== ServiceAccount IAM Role Analysis (excluding kube-system) ===${NC}"
    echo
    
    # Frontend ServiceAccounts
    local frontend_count=$(echo "$frontend_sa" | grep -c '^' 2>/dev/null || echo "0")
    if [[ -n "$frontend_sa" && "$frontend_count" -gt 0 ]]; then
        echo -e "${GREEN}🔐 Frontend Cluster ServiceAccounts requiring IAM trust (${frontend_count}):${NC}"
        printf "%-25s %-35s %s\n" "NAMESPACE" "SERVICE_ACCOUNT" "IAM_ROLE"
        printf "%-25s %-35s %s\n" "---------" "---------------" "--------"
        echo "$frontend_sa" | while IFS=$'\t' read -r namespace name role; do
            [[ -n "$namespace" ]] && printf "%-25s %-35s %s\n" "$namespace" "$name" "$(basename "$role")"
        done
        echo
    else
        echo -e "${YELLOW}⚠️  No ServiceAccounts with IAM roles found in frontend cluster (excluding kube-system)${NC}"
        echo
    fi
    
    # Create temporary files for comparison  
    local temp_frontend=$(mktemp)
    local temp_backend=$(mktemp)
    
    # Create comparable format (namespace:name)
    echo "$frontend_sa" | awk -F'\t' '{if(NF>=2) print $1":"$2}' | sort > "$temp_frontend"
    echo "$backend_sa" | awk -F'\t' '{if(NF>=2) print $1":"$2}' | sort > "$temp_backend"
    
    # Find ServiceAccounts that exist in frontend but not in backend
    local frontend_only=$(comm -23 "$temp_frontend" "$temp_backend")
    local frontend_only_count=$(echo "$frontend_only" | grep -c '^' 2>/dev/null || echo "0")
    
    if [[ "$frontend_only_count" -gt 0 ]]; then
        echo -e "${RED}🚨 IAM Roles needing Backend OIDC trust (${frontend_only_count}):${NC}"
        echo -e "${YELLOW}These IAM roles need to trust the backend cluster's OIDC provider${NC}"
        echo
        
        # Show detailed info for roles that need backend trust
        echo "$frontend_only" | while read sa_key; do
            if [[ -n "$sa_key" ]]; then
                local namespace=$(echo "$sa_key" | cut -d: -f1)
                local name=$(echo "$sa_key" | cut -d: -f2)
                
                # Find the IAM role for this SA
                local role_arn=$(echo "$frontend_sa" | grep "^$namespace\t$name\t" | cut -f3)
                local role_name=$(basename "$role_arn")
                
                echo -e "  ${RED}🔧 $sa_key${NC}"
                echo -e "     Role: ${BLUE}$role_name${NC}"
                echo -e "     ARN:  $role_arn"
                echo
            fi
        done
    else
        echo -e "${GREEN}✅ All frontend ServiceAccounts already exist in backend cluster${NC}"
        echo -e "${GREEN}   No additional OIDC trust configuration needed${NC}"
        echo
    fi
    
    # Summary with actionable information
    echo -e "${BLUE}📊 OIDC Trust Setup Summary:${NC}"
    echo "  Frontend SA with IAM roles: $frontend_count"
    echo "  Roles needing backend OIDC trust: $frontend_only_count"
    
    # Cleanup
    rm -f "$temp_frontend" "$temp_backend"
}