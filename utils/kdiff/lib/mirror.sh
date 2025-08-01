#!/bin/bash

# lib/mirror.sh - Service Mirror Management functions

compare_mirror() {
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    echo -e "${BLUE}🔍 Analyzing service mirror setup between clusters...${NC}"
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    echo "Fetching frontend mirror services..."
    
    local frontend_services
    frontend_services=$(kubectl --context="$FRONTEND_CLUSTER" get svc -A --no-headers 2>/dev/null)
    
    if [ -z "$frontend_services" ]; then
        echo -e "${RED}❌ Could not fetch services from frontend cluster${NC}"
        return 1
    fi
    
    local frontend_mirrors
    frontend_mirrors=$(echo "$frontend_services" | grep "\-eks" | awk '{print $1"\t"$2"\t"$3}')
    
    if [ -z "$frontend_mirrors" ]; then
        echo -e "${YELLOW}⚠️  No mirror services found in frontend cluster${NC}"
        echo -e "${GRAY}Looking for services with pattern: <service-name>-<cluster-name> (containing 'eks')${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}=== Frontend Mirror Services Analysis ===${NC}"
    echo
    
    local mirror_count=0
    local missing_backend_count=0
    
    
    while IFS=$'\t' read -r namespace svc_name svc_type; do
        if [ -n "$svc_name" ] && echo "$svc_name" | grep -q "\-eks"; then
           
            local base_svc
            local cluster_name
            

            cluster_name=$(echo "$svc_name" | grep -o '[^-]*-[^-]*-[^-]*-eks$' | head -1)
            if [ -n "$cluster_name" ]; then
                base_svc=$(echo "$svc_name" | sed "s/-${cluster_name}$//")
            else
              
                base_svc=$(echo "$svc_name" | sed 's/-[^-]*-[^-]*-[^-]*-eks$//')
                cluster_name=$(echo "$svc_name" | sed 's/.*-\([^-]*-[^-]*-[^-]*-eks\)$/\1/')
            fi
            
            mirror_count=$((mirror_count + 1))
            
            echo -e "${GREEN}🔗 Mirror Service Found:${NC}"
            echo "  Namespace: $namespace"
            echo "  Mirror Service: $svc_name"
            echo "  Base Service: $base_svc"
            echo "  Target Cluster: $cluster_name"
            
         
            local backend_check
            backend_check=$(kubectl --context="$BACKEND_CLUSTER" get svc "$base_svc" -n "$namespace" --no-headers 2>/dev/null)
            
            if [ -n "$backend_check" ]; then
                echo -e "  Backend Status: ${GREEN}✅ Service '$base_svc' exists${NC}"
                
               
                local frontend_selector
                local backend_selector
                frontend_selector=$(kubectl --context="$FRONTEND_CLUSTER" get svc "$svc_name" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
                backend_selector=$(kubectl --context="$BACKEND_CLUSTER" get svc "$base_svc" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
                
                echo "  Frontend Selector: $frontend_selector"
                echo "  Backend Selector: $backend_selector"
                
            else
                echo -e "  Backend Status: ${RED}❌ Service '$base_svc' missing in backend cluster${NC}"
                missing_backend_count=$((missing_backend_count + 1))
            fi
            
            echo
        fi
    done <<< "$frontend_mirrors"
    
    # Summary
    echo -e "${BLUE}📊 Mirror Services Summary:${NC}"
    echo "  Total mirror services in frontend: $mirror_count"
    echo "  Missing backend services: $missing_backend_count"
    
    if [ $missing_backend_count -eq 0 ] && [ $mirror_count -gt 0 ]; then
        echo -e "${GREEN}✅ All mirror services have corresponding backend services${NC}"
    elif [ $missing_backend_count -gt 0 ]; then
        echo -e "${RED}🚨 Some mirror services are missing backend targets${NC}"
    fi
}

create_mirror() {
    local target_service="$1"
    
    if ! load_cluster_config; then
        prompt_cluster_setup
        load_cluster_config
    fi
    
    if [ -n "$target_service" ]; then
        echo -e "${BLUE}🛠️  Creating mirror for specific service: ${CYAN}$target_service${NC}"
    else
        echo -e "${BLUE}🛠️  Preparing to create mirror services in backend cluster...${NC}"
    fi
    echo -e "Frontend: ${GREEN}$FRONTEND_CLUSTER${NC}"
    echo -e "Backend:  ${GREEN}$BACKEND_CLUSTER${NC}"
    echo
    
    # Get frontend mirror services
    echo "Analyzing frontend mirror services for backend creation..."
    
    local frontend_services
    frontend_services=$(kubectl --context="$FRONTEND_CLUSTER" get svc -A --no-headers 2>/dev/null)
    
    if [ -z "$frontend_services" ]; then
        echo -e "${RED}❌ Could not fetch services from frontend cluster${NC}"
        return 1
    fi
    
    # Filter for mirror services
    local frontend_mirrors
    if [ -n "$target_service" ]; then
        frontend_mirrors=$(echo "$frontend_services" | grep "\-eks" | grep "$target_service" | awk '{print $1"\t"$2"\t"$3}')
        if [ -z "$frontend_mirrors" ]; then
            echo -e "${YELLOW}⚠️  No mirror service found for '$target_service' in frontend cluster${NC}"
            return 0
        fi
    else
        frontend_mirrors=$(echo "$frontend_services" | grep "\-eks" | awk '{print $1"\t"$2"\t"$3}')
        if [ -z "$frontend_mirrors" ]; then
            echo -e "${YELLOW}⚠️  No mirror services found in frontend cluster${NC}"
            return 0
        fi
    fi
    
    # Create temp file for services to create
    local services_file
    services_file=$(mktemp)
    
    local creation_plan=""
    local skip_plan=""
    local count=0
    
    echo -e "${YELLOW}=== Backend Mirror Creation Analysis ===${NC}"
    echo
    
    
    while IFS=$'\t' read -r namespace svc_name svc_type; do
        if [ -n "$svc_name" ] && echo "$svc_name" | grep -q "\-eks"; then
            
            local base_svc
            local cluster_name
            
            cluster_name=$(echo "$svc_name" | grep -o '[^-]*-[^-]*-[^-]*-eks$' | head -1)
            if [ -n "$cluster_name" ]; then
                base_svc=$(echo "$svc_name" | sed "s/-${cluster_name}$//")
            else
                base_svc=$(echo "$svc_name" | sed 's/-[^-]*-[^-]*-[^-]*-eks$//')
            fi
            
            
            if [ -n "$target_service" ] && [ "$base_svc" != "$target_service" ]; then
                continue
            fi
            
            
            local backend_base_exists
            backend_base_exists=$(kubectl --context="$BACKEND_CLUSTER" get svc "$base_svc" -n "$namespace" --no-headers 2>/dev/null)
            
            if [ -n "$backend_base_exists" ]; then

                local backend_mirror_exists
                backend_mirror_exists=$(kubectl --context="$BACKEND_CLUSTER" get svc "$svc_name" -n "$namespace" --no-headers 2>/dev/null)
                
                if [ -z "$backend_mirror_exists" ]; then
                    
                    local backend_selector
                    backend_selector=$(kubectl --context="$BACKEND_CLUSTER" get svc "$base_svc" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
                    
                    echo -e "${GREEN}📋 Mirror service ready for backend creation:${NC}"
                    echo "  Namespace: $namespace"
                    echo "  Frontend Mirror: $svc_name"
                    echo "  Backend Base Service: $base_svc"
                    echo "  Backend Selector: $backend_selector"
                    echo "  Will create in backend: $svc_name"
                    echo
                    
                    
                    echo "$namespace:$svc_name:$base_svc:$backend_selector" >> "$services_file"
                    creation_plan="${creation_plan}  • $namespace/$svc_name (copying selector from $base_svc)\n"
                    count=$((count + 1))
                else
                    echo -e "${GRAY}⏭️  Skipping $namespace/$svc_name (mirror already exists in backend)${NC}"
                    skip_plan="${skip_plan}  • $namespace/$svc_name (already exists)\n"
                    echo
                fi
            else
                echo -e "${YELLOW}⚠️  Skipping $namespace/$svc_name (base service '$base_svc' not found in backend)${NC}"
                skip_plan="${skip_plan}  • $namespace/$svc_name (base service '$base_svc' not found)\n"
                echo
            fi
        fi
    done <<< "$frontend_mirrors"
    
    if [ $count -eq 0 ]; then
        if [ -n "$target_service" ]; then
            echo -e "${YELLOW}⚠️  No mirror creation needed for service '$target_service'${NC}"
        else
            echo -e "${GREEN}✅ All necessary mirror services already exist in backend cluster${NC}"
        fi
        rm -f "$services_file"
        return 0
    fi
    
    
    echo -e "${YELLOW}=== Backend Mirror Services Creation Plan ===${NC}"
    if [ -n "$target_service" ]; then
        echo -e "Mirror service for ${CYAN}$target_service${NC} will be created in ${GREEN}$BACKEND_CLUSTER${NC}:"
    else
        echo -e "The following mirror services will be created in ${GREEN}$BACKEND_CLUSTER${NC}:"
    fi
    echo
    echo -e "$creation_plan"
    echo -e "Total services to create: $count"
    
    
    if [ -n "$skip_plan" ]; then
        echo
        echo -e "${GRAY}Services that will NOT be created:${NC}"
        echo -e "$skip_plan"
    fi
    echo
    
    
    read -p "Create these mirror services in backend cluster? (y/N): " -n 1 -r
    echo
    if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
        echo -e "${YELLOW}Mirror creation cancelled${NC}"
        rm -f "$services_file"
        return 0
    fi
    
    
    echo -e "${BLUE}🚀 Creating mirror services in backend cluster...${NC}"
    echo
    
    local created_count=0
    local failed_count=0
    
    while IFS=':' read -r namespace mirror_name base_svc selector; do
        echo -e "Creating ${CYAN}$namespace/$mirror_name${NC} in backend cluster..."
        
        
        echo -e "  ${GRAY}Debug - Base service: $base_svc${NC}"
        echo -e "  ${GRAY}Debug - Selector: $selector${NC}"
        
        
        local base_svc_yaml
        base_svc_yaml=$(kubectl --context="$BACKEND_CLUSTER" get svc "$base_svc" -n "$namespace" -o yaml 2>/dev/null)
        
        if [ -z "$base_svc_yaml" ]; then
            echo -e "  ${RED}❌ Could not get base service spec${NC}"
            failed_count=$((failed_count + 1))
            continue
        fi
        
        
        local ports_yaml
        ports_yaml=$(echo "$base_svc_yaml" | sed -n '/^  ports:/,/^  [a-zA-Z]/p' | sed '$d' | sed 's/^  //')
        
        
        if [ -z "$ports_yaml" ] || ! echo "$ports_yaml" | grep -q "port:"; then
            ports_yaml="ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 80"
        fi
        
        echo -e "  ${GRAY}Debug - Ports extracted:${NC}"
        echo "$ports_yaml" | sed 's/^/    /'
        
        
        local yaml_selector
        if echo "$selector" | grep -q "^{"; then
            yaml_selector=$(echo "$selector" | sed 's/[{}"]//g' | sed 's/,/\n/g' | sed 's/:/: /' | sed 's/^/    /')
        else
            yaml_selector="    $selector"
        fi
        
        echo -e "  ${GRAY}Debug - YAML selector:${NC}"
        echo "$yaml_selector"
        
        
        local formatted_ports
        formatted_ports=$(echo "$base_svc_yaml" | sed -n '/^  ports:/,/^  [a-zA-Z]/p' | sed '$d')
        
        
        if [ -z "$formatted_ports" ] || ! echo "$formatted_ports" | grep -q "port:"; then
            formatted_ports="  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 80"
        fi
        
        echo -e "  ${GRAY}Debug - Formatted ports:${NC}"
        echo "$formatted_ports" | sed 's/^/    /'
        
        
        local temp_yaml
        temp_yaml=$(mktemp)
        
        cat > "$temp_yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $mirror_name
  namespace: $namespace
  labels:
    mirror.linkerd.io/exported-service: $base_svc
    mirror.linkerd.io/cluster-name: $FRONTEND_CLUSTER
spec:
  selector:
$yaml_selector
$formatted_ports
EOF
        

        echo -e "  ${GRAY}Debug - Generated YAML:${NC}"
        cat "$temp_yaml" | sed 's/^/    /'
        
        
        local apply_output
        apply_output=$(kubectl --context="$BACKEND_CLUSTER" apply -f "$temp_yaml" 2>&1)
        local apply_result=$?
        
        if [ $apply_result -eq 0 ]; then
            echo -e "  ${GREEN}✅ Successfully created $namespace/$mirror_name in backend${NC}"
            created_count=$((created_count + 1))
        else
            echo -e "  ${RED}❌ Failed to create $namespace/$mirror_name in backend${NC}"
            echo -e "  ${RED}Error: $apply_output${NC}"
            failed_count=$((failed_count + 1))
        fi
        
        
        rm -f "$temp_yaml"
        
    done < "$services_file"
    
    
    rm -f "$services_file"
    
    echo
    echo -e "${BLUE}📊 Backend Creation Summary:${NC}"
    echo "  Successfully created: $created_count"
    echo "  Failed: $failed_count"
    
    if [ $created_count -gt 0 ]; then
        echo -e "${GREEN}🎉 Mirror services created successfully in backend cluster!${NC}"
        echo -e "${YELLOW}💡 Run 'kdiff mirror' to verify the setup${NC}"
    fi
}