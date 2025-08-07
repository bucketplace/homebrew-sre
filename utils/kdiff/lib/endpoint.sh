#!/bin/bash

# lib/endpoint.sh - Ingress Endpoint Analysis functions

resolve_all_dns() {
    local hostname="$1"
    
    if [ -z "$hostname" ]; then
        echo "N/A"
        return
    fi
    
    dig +short A "$hostname" | sort
}

analyze_cluster_endpoints() {
    local cluster_context="$1"
    local cluster_name="$2"
    
    echo -e "${BLUE}🔍 Analyzing sample endpoints for ${GREEN}$cluster_name${NC}" >&2
    echo >&2
    
    local found_any=false
    local endpoint_patterns=""
    
    local contour_proxies
    contour_proxies=$(kubectl --context="$cluster_context" get httpproxies -A --no-headers 2>/dev/null)
    
    if [ -n "$contour_proxies" ]; then
        local contour_total
        contour_total=$(echo "$contour_proxies" | wc -l)
        local contour_sample
        contour_sample=$(echo "$contour_proxies" | shuf | head -5)
        
        echo -e "${CYAN}📋 Contour HTTPProxies (sampling 5 out of $contour_total):${NC}" >&2
        
        while read -r line; do
            local namespace name
            namespace=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            
            if [ -n "$namespace" ] && [ -n "$name" ]; then
                local fqdn
                fqdn=$(kubectl --context="$cluster_context" get httpproxy "$name" -n "$namespace" -o jsonpath='{.spec.virtualhost.fqdn}' 2>/dev/null)
                
                if [ -n "$fqdn" ]; then
                    echo -e "  ${GRAY}Checking: $fqdn${NC}" >&2
                    local a_records
                    a_records=$(resolve_all_dns "$fqdn")
                    
                    if [ -n "$a_records" ] && [ "$a_records" != "N/A" ]; then
                        echo -e "    ${GREEN}→${NC}" >&2
                        echo "$a_records" | while read -r ip; do
                            if [ -n "$ip" ]; then
                                echo -e "    ${GREEN}[$ip]${NC}" >&2
                            fi
                        done
                        
                        local record_set
                        record_set=$(echo "$a_records" | tr '\n' ',' | sed 's/,$//')
                        endpoint_patterns="${endpoint_patterns}${cluster_name}:${record_set}|"
                    fi
                fi
            fi
        done <<< "$contour_sample"
        echo >&2
        found_any=true
    fi
    
    local emissary_mappings
    emissary_mappings=$(kubectl --context="$cluster_context" get mappings -A --no-headers 2>/dev/null)
    
    if [ -n "$emissary_mappings" ]; then
        local emissary_total
        emissary_total=$(echo "$emissary_mappings" | wc -l)
        local emissary_sample
        emissary_sample=$(echo "$emissary_mappings" | shuf | head -5)
        
        echo -e "${CYAN}🌐 Emissary Mappings (sampling 5 out of $emissary_total):${NC}" >&2
        
        while read -r line; do
            local namespace name
            namespace=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            
            if [ -n "$namespace" ] && [ -n "$name" ]; then
                local host
                host=$(kubectl --context="$cluster_context" get mapping "$name" -n "$namespace" -o jsonpath='{.spec.host}' 2>/dev/null)
                
                if [ -n "$host" ] && [ "$host" != "<none>" ]; then
                    echo -e "  ${GRAY}Checking: $host${NC}" >&2
                    local a_records
                    a_records=$(resolve_all_dns "$host")
                    
                    if [ -n "$a_records" ] && [ "$a_records" != "N/A" ]; then
                        echo -e "    ${GREEN}→${NC}" >&2
                        echo "$a_records" | while read -r ip; do
                            if [ -n "$ip" ]; then
                                echo -e "    ${GREEN}[$ip]${NC}" >&2
                            fi
                        done
                        
                        local record_set
                        record_set=$(echo "$a_records" | tr '\n' ',' | sed 's/,$//')
                        endpoint_patterns="${endpoint_patterns}${cluster_name}:${record_set}|"
                    fi
                fi
            fi
        done <<< "$emissary_sample"
        echo >&2
        found_any=true
    fi
    
    local nginx_ingresses
    nginx_ingresses=$(kubectl --context="$cluster_context" get ingress -A --no-headers 2>/dev/null)
    
    if [ -n "$nginx_ingresses" ]; then
        local nginx_total
        nginx_total=$(echo "$nginx_ingresses" | wc -l)
        local nginx_sample
        nginx_sample=$(echo "$nginx_ingresses" | shuf | head -5)
        
        echo -e "${CYAN}🔗 NGINX Ingresses (sampling 5 out of $nginx_total):${NC}" >&2
        
        while read -r line; do
            local namespace name
            namespace=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            
            if [ -n "$namespace" ] && [ -n "$name" ]; then
                local hosts
                hosts=$(kubectl --context="$cluster_context" get ingress "$name" -n "$namespace" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
                
                if [ -n "$hosts" ] && [ "$hosts" != "<none>" ]; then
                    echo -e "  ${GRAY}Checking: $hosts${NC}" >&2
                    local a_records
                    a_records=$(resolve_all_dns "$hosts")
                    
                    if [ -n "$a_records" ] && [ "$a_records" != "N/A" ]; then
                        echo -e "    ${GREEN}→${NC}" >&2
                        echo "$a_records" | while read -r ip; do
                            if [ -n "$ip" ]; then
                                echo -e "    ${GREEN}[$ip]${NC}" >&2
                            fi
                        done
                        
                        local record_set
                        record_set=$(echo "$a_records" | tr '\n' ',' | sed 's/,$//')
                        endpoint_patterns="${endpoint_patterns}${cluster_name}:${record_set}|"
                    fi
                fi
            fi
        done <<< "$nginx_sample"
        echo >&2
        found_any=true
    fi
    
    if [ "$found_any" = false ]; then
        echo -e "${YELLOW}⚠️  No ingress endpoints found in $cluster_name${NC}" >&2
        echo >&2
    fi
    
    echo "$endpoint_patterns"
}

compare_endpoints() {
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    echo -e "${BLUE}🌐 Analyzing Ingress Endpoints between clusters...${NC}"
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    if ! command -v dig >/dev/null 2>&1; then
        echo -e "${RED}❌ 'dig' command not found. Please install bind-utils or dnsutils${NC}"
        echo -e "${YELLOW}💡 Install with: brew install bind (macOS) or apt-get install dnsutils (Ubuntu)${NC}"
        return 1
    fi
    
    if ! command -v shuf >/dev/null 2>&1; then
        echo -e "${RED}❌ 'shuf' command not found. Please install coreutils${NC}"
        echo -e "${YELLOW}💡 Install with: brew install coreutils (macOS)${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Frontend Cluster Endpoints ===${NC}"
    analyze_cluster_endpoints "$FRONTEND_CLUSTER" "$FRONTEND_CLUSTER" >/dev/null
    
    echo -e "${YELLOW}=== Backend Cluster Endpoints ===${NC}"
    analyze_cluster_endpoints "$BACKEND_CLUSTER" "$BACKEND_CLUSTER" >/dev/null
    
    echo -e "${GRAY}Analysis complete! ELB endpoint patterns shown above.${NC}"
}