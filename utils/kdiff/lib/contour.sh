#!/bin/bash

# lib/contour.sh - Contour HTTPProxy comparison functions

compare_contour() {
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    echo -e "${BLUE}Comparing Contour HTTPProxies between clusters...${NC}"
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    # Get Contour HTTPProxies from both clusters
    echo "Fetching Contour HTTPProxies..."

    local frontend_proxies
    frontend_proxies=$(kubectl --context="$FRONTEND_CLUSTER" get httpproxies -A -o json 2>/dev/null | \
        jq -r '.items[] |
        .metadata.namespace + "\t" +
        .metadata.name + "\t" +
        (.spec.virtualhost.fqdn // "<none>") + "\t" +
        (.spec.ingressClassName // "<none>") + "\t" +
        ([.spec.routes[]?.conditions[]?.prefix // empty] | join(",") | if . == "" then "<none>" else . end)' | sort)

    local backend_proxies
    backend_proxies=$(kubectl --context="$BACKEND_CLUSTER" get httpproxies -A -o json 2>/dev/null | \
        jq -r '.items[] |
        .metadata.namespace + "\t" +
        .metadata.name + "\t" +
        (.spec.virtualhost.fqdn // "<none>") + "\t" +
        (.spec.ingressClassName // "<none>") + "\t" +
        ([.spec.routes[]?.conditions[]?.prefix // empty] | join(",") | if . == "" then "<none>" else . end)' | sort)
    
    if [ -z "$frontend_proxies" ] && [ -z "$backend_proxies" ]; then
        echo -e "${YELLOW}⚠️  No Contour HTTPProxies found in either cluster${NC}"
        return 0
    fi
    
    # Show results
    echo -e "${YELLOW}=== Contour HTTPProxy Comparison Results ===${NC}"
    echo
    
    # Frontend HTTPProxies
    local frontend_count
    frontend_count=$(echo "$frontend_proxies" | grep -c '^' 2>/dev/null || echo "0")
    if [ -n "$frontend_proxies" ] && [ "$frontend_count" -gt 0 ]; then
        echo -e "${GREEN}🔗 Frontend Cluster HTTPProxies (${frontend_count}):${NC}"
        printf "%-20s %-30s %-40s %-15s %s\n" "NAMESPACE" "HTTPPROXY_NAME" "FQDN" "INGRESS_CLASS" "PREFIX"
        printf "%-20s %-30s %-40s %-15s %s\n" "---------" "--------------" "----" "-------------" "------"
        echo "$frontend_proxies" | while IFS=$'\t' read -r namespace name fqdn ingressClassName prefix; do
            [ -n "$namespace" ] && printf "%-20s %-30s %-40s %-15s %s\n" "$namespace" "$name" "${fqdn:-<none>}" "${ingressClassName:-<none>}" "${prefix:-<none>}"
        done
        echo
    else
        echo -e "${YELLOW}⚠️  No Contour HTTPProxies found in frontend cluster${NC}"
        echo
    fi
    
    # Backend HTTPProxies
    local backend_count
    backend_count=$(echo "$backend_proxies" | grep -c '^' 2>/dev/null || echo "0")
    if [ -n "$backend_proxies" ] && [ "$backend_count" -gt 0 ]; then
        echo -e "${GREEN}🔗 Backend Cluster HTTPProxies (${backend_count}):${NC}"
        printf "%-20s %-30s %-40s %-15s %s\n" "NAMESPACE" "HTTPPROXY_NAME" "FQDN" "INGRESS_CLASS" "PREFIX"
        printf "%-20s %-30s %-40s %-15s %s\n" "---------" "--------------" "----" "-------------" "------"
        echo "$backend_proxies" | while IFS=$'\t' read -r namespace name fqdn ingressClassName prefix; do
            [ -n "$namespace" ] && printf "%-20s %-30s %-40s %-15s %s\n" "$namespace" "$name" "${fqdn:-<none>}" "${ingressClassName:-<none>}" "${prefix:-<none>}"
        done
        echo
    else
        echo -e "${YELLOW}⚠️  No Contour HTTPProxies found in backend cluster${NC}"
        echo
    fi
    
    # Comparison analysis if both clusters have proxies
    if [ "$frontend_count" -gt 0 ] || [ "$backend_count" -gt 0 ]; then
        # Create temporary files for comparison
        local temp_frontend
        local temp_backend
        temp_frontend=$(mktemp)
        temp_backend=$(mktemp)
        
        # Create comparable format (namespace:name) using simple awk
        echo "$frontend_proxies" | awk -F$'\t' 'NF>=2 {print $1":"$2}' | sort > "$temp_frontend"
        echo "$backend_proxies" | awk -F$'\t' 'NF>=2 {print $1":"$2}' | sort > "$temp_backend"
        
        # Find differences
        local frontend_only
        local backend_only
        local common
        frontend_only=$(comm -23 "$temp_frontend" "$temp_backend")
        backend_only=$(comm -13 "$temp_frontend" "$temp_backend")
        common=$(comm -12 "$temp_frontend" "$temp_backend")
        
        local frontend_only_count
        local backend_only_count
        local common_count
        frontend_only_count=$(echo "$frontend_only" | grep -c '^' 2>/dev/null || echo "0")
        backend_only_count=$(echo "$backend_only" | grep -c '^' 2>/dev/null || echo "0")
        common_count=$(echo "$common" | grep -c '^' 2>/dev/null || echo "0")
        
        echo -e "${BLUE}🔍 Analysis:${NC}"
        
        if [ "$frontend_only_count" -gt 0 ]; then
            echo -e "${RED}🚨 Missing in Backend cluster (${frontend_only_count} HTTPProxies):${NC}"
            echo "$frontend_only" | while read -r line; do
                if [ -n "$line" ]; then
                    local namespace
                    local name
                    namespace=$(echo "$line" | cut -d: -f1)
                    name=$(echo "$line" | cut -d: -f2)
                    local proxy_details
                    proxy_details=$(echo "$frontend_proxies" | grep "^$namespace\t$name\t" | head -1)
                    local fqdn
                    local ingressClassName
                    local prefix
                    fqdn=$(echo "$proxy_details" | cut -f3)
                    ingressClassName=$(echo "$proxy_details" | cut -f4)
                    prefix=$(echo "$proxy_details" | cut -f5)

                    echo -e "  - ${RED}$line${NC}"
                    echo -e "    FQDN: ${fqdn:-<none>}"
                    echo -e "    IngressClass: ${ingressClassName:-<none>}"
                    echo -e "    Prefix: ${prefix:-<none>}"
                fi
            done
            echo
        fi
        
        if [ "$common_count" -gt 0 ]; then
            echo -e "${GREEN}✅ Common HTTPProxies: ${common_count}${NC}"
            echo
        fi
        
        # Cleanup
        rm -f "$temp_frontend" "$temp_backend"
    fi
    
    echo -e "${BLUE}📊 Summary:${NC}"
    echo "  Frontend HTTPProxies: $frontend_count"
    echo "  Backend HTTPProxies:  $backend_count"
    echo "  Missing in backend: $frontend_only_count"
}