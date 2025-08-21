#!/bin/bash

# lib/emissary.sh - Emissary Mapping comparison functions

compare_emissary() {
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    echo -e "${BLUE}Comparing Emissary Mappings between clusters...${NC}"
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    # Get Emissary Mappings from both clusters
    echo "Fetching Emissary Mappings..."
    
    local frontend_mappings=$(kubectl --context="$FRONTEND_CLUSTER" get mappings -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.host}{"\t"}{.spec.prefix}{"\t"}{.spec.ambassador_id}{"\n"}{end}' 2>/dev/null | sort)
    
    local backend_mappings=$(kubectl --context="$BACKEND_CLUSTER" get mappings -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.host}{"\t"}{.spec.prefix}{"\t"}{.spec.ambassador_id}{"\n"}{end}' 2>/dev/null | sort)
    
    if [[ -z "$frontend_mappings" && -z "$backend_mappings" ]]; then
        echo -e "${YELLOW}⚠️  No Emissary Mappings found in either cluster${NC}"
        return 0
    fi
    
    # Show results
    echo -e "${YELLOW}=== Emissary Mapping Comparison Results ===${NC}"
    echo
    
    # Frontend Mappings
    local frontend_count=$(echo "$frontend_mappings" | grep -c '^' 2>/dev/null || echo "0")
    if [[ -n "$frontend_mappings" && "$frontend_count" -gt 0 ]]; then
        echo -e "${GREEN}🌐 Frontend Cluster Mappings (${frontend_count}):${NC}"
        printf "%-20s %-30s %-40s %-20s %s\n" "NAMESPACE" "MAPPING_NAME" "HOST" "PREFIX" "AMBASSADOR_ID"
        printf "%-20s %-30s %-40s %-20s %s\n" "---------" "------------" "----" "------" "-------------"
        echo "$frontend_mappings" | while IFS=$'\t' read -r namespace name host prefix ambassador_id; do
            [[ -n "$namespace" ]] && printf "%-20s %-30s %-40s %-20s %s\n" "$namespace" "$name" "${host:-<none>}" "${prefix:-<none>}" "${ambassador_id:-<none>}"
        done
        echo
    else
        echo -e "${YELLOW}⚠️  No Emissary Mappings found in frontend cluster${NC}"
        echo
    fi
    
    # Backend Mappings
    local backend_count=$(echo "$backend_mappings" | grep -c '^' 2>/dev/null || echo "0")
    if [[ -n "$backend_mappings" && "$backend_count" -gt 0 ]]; then
        echo -e "${GREEN}🌐 Backend Cluster Mappings (${backend_count}):${NC}"
        printf "%-20s %-30s %-40s %-20s %s\n" "NAMESPACE" "MAPPING_NAME" "HOST" "PREFIX" "AMBASSADOR_ID"
        printf "%-20s %-30s %-40s %-20s %s\n" "---------" "------------" "----" "------" "-------------"
        echo "$backend_mappings" | while IFS=$'\t' read -r namespace name host prefix ambassador_id; do
            [[ -n "$namespace" ]] && printf "%-20s %-30s %-40s %-20s %s\n" "$namespace" "$name" "${host:-<none>}" "${prefix:-<none>}" "${ambassador_id:-<none>}"
        done
        echo
    else
        echo -e "${YELLOW}⚠️  No Emissary Mappings found in backend cluster${NC}"
        echo
    fi
    
    # Comparison analysis if both clusters have mappings
    if [[ "$frontend_count" -gt 0 || "$backend_count" -gt 0 ]]; then
        # Create temporary files for comparison
        local temp_frontend=$(mktemp)
        local temp_backend=$(mktemp)
        
        # Create comparable format (namespace:name)
        echo "$frontend_mappings" | awk -F'\t' '{if(NF>=2) print $1":"$2}' | sort > "$temp_frontend"
        echo "$backend_mappings" | awk -F'\t' '{if(NF>=2) print $1":"$2}' | sort > "$temp_backend"
        
        # Find differences
        local frontend_only=$(comm -23 "$temp_frontend" "$temp_backend")
        local common=$(comm -12 "$temp_frontend" "$temp_backend")
        
        local frontend_only_count=$(echo "$frontend_only" | grep -c '^' 2>/dev/null || echo "0")
        local common_count=$(echo "$common" | grep -c '^' 2>/dev/null || echo "0")
        
        echo -e "${BLUE}🔍 Analysis:${NC}"
        
        if [[ "$frontend_only_count" -gt 0 ]]; then
            echo -e "${RED}🚨 Missing in Backend cluster (${frontend_only_count} mappings):${NC}"
            echo "$frontend_only" | while read line; do
                if [[ -n "$line" ]]; then
                    local namespace=$(echo "$line" | cut -d: -f1)
                    local name=$(echo "$line" | cut -d: -f2)
                    local mapping_details=$(echo "$frontend_mappings" | grep "^$namespace\t$name\t" | head -1)
                    local host=$(echo "$mapping_details" | cut -f3)
                    local prefix=$(echo "$mapping_details" | cut -f4)
                    local ambassador_id=$(echo "$mapping_details" | cut -f5)
                    
                    echo -e "  - ${RED}$line${NC}"
                    echo -e "    Host: ${host:-<none>}, Prefix: ${prefix:-<none>}, Ambassador ID: ${ambassador_id:-<none>}"
                fi
            done
            echo
        fi
    
        
        if [[ "$common_count" -gt 0 ]]; then
            echo -e "${GREEN}✅ Common mappings: ${common_count}${NC}"
            echo
        fi
        
        # Cleanup
        rm -f "$temp_frontend" "$temp_backend"
    fi
    
    echo -e "${BLUE}📊 Summary:${NC}"
    echo "  Frontend mappings: $frontend_count"
    echo "  Backend mappings:  $backend_count"
    echo "  Missing in backend: $frontend_only_count"
}