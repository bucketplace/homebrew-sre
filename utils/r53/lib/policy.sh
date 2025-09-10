#!/bin/bash

load_a_records() {
    local records_file="$TEMP_DIR/records.json"
    
    echo -e "${CYAN}Loading A records from Route 53...${NC}"
    
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --profile "$PROFILE" \
        --output json > "$records_file"
    
    echo -e "${GREEN}Records loaded successfully${NC}"
    echo ""
}

load_all_records() {
    local records_file="$TEMP_DIR/records.json"
    
    echo -e "${CYAN}Loading all records from Route 53...${NC}"
    
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --profile "$PROFILE" \
        --output json > "$records_file"
    
    echo -e "${GREEN}Records loaded successfully${NC}"
    echo ""
}

choose_filter() {
    local filter_options=("Show all records" "Filter by record type" "Search by name pattern" "Show only simple records")
    local filter_descriptions=(
        "Display all DNS records"
        "Filter by A, AAAA, CNAME, MX, etc."
        "Search records by name pattern"
        "Show records without routing policies"
    )
    
    local total=${#filter_options[@]}
    local selected=0
    
    echo -e "${BLUE}Record Filter Options (up/down arrows, Enter to select):${NC}"
    echo ""
    
    printf "\033[?25l"
    
    draw_filter_menu() {
        for i in "${!filter_options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}> ${filter_options[i]}${NC} - ${filter_descriptions[i]}"
            else
                echo -e "  ${filter_options[i]} - ${filter_descriptions[i]}"
            fi
        done
    }
    
    draw_filter_menu
    
    while true; do
        read -rsn1 key
        
        case "$key" in
            $'\033')
                read -rsn2 key
                case "$key" in
                    '[A')
                        if [[ $selected -gt 0 ]]; then
                            selected=$((selected - 1))
                            tput cuu $total
                            draw_filter_menu
                        fi
                        ;;
                    '[B')
                        if [[ $selected -lt $((total - 1)) ]]; then
                            selected=$((selected + 1))
                            tput cuu $total
                            draw_filter_menu
                        fi
                        ;;
                esac
                ;;
            '')
                printf "\033[?25h"
                tput cuu $total
                for i in $(seq 1 $((total + 3))); do
                    tput el
                    echo ""
                done
                tput cuu $((total + 3))
                
                local chosen_filter="${filter_options[selected]}"
                echo -e "${GREEN}Selected: ${chosen_filter}${NC}"
                echo ""
                
                local search_filter=""
                local type_filter=""
                
                case "$chosen_filter" in
                    "Show all records")
                        ;;
                    "Filter by record type")
                        echo "Available record types: A, AAAA, CNAME, MX, TXT, NS, SOA, PTR, SRV, CAA"
                        read -p "Enter record type: " type_filter
                        ;;
                    "Search by name pattern")
                        read -p "Enter name pattern to search: " search_filter
                        ;;
                    "Show only simple records")
                        type_filter="simple"
                        ;;
                esac
                
                break
                ;;
            'q'|'Q')
                printf "\033[?25h"
                echo ""
                echo "Goodbye!"
                return 0
                ;;
        esac
    done
}

policy_manager() {
    local records_file="$TEMP_DIR/records.json"
    
    local filter_options=("Show all records" "Filter by record type" "Search by name pattern" "Show only simple records")
    local filter_descriptions=(
        "Display all DNS records"
        "Filter by A, AAAA, CNAME, MX, etc."
        "Search records by name pattern"
        "Show records without routing policies"
    )
    
    local total=${#filter_options[@]}
    local selected=0
    
    echo -e "${BLUE}Record Filter Options (up/down arrows, Enter to select):${NC}"
    echo ""
    
    printf "\033[?25l"
    
    draw_filter_menu() {
        for i in "${!filter_options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}> ${filter_options[i]}${NC} - ${filter_descriptions[i]}"
            else
                echo -e "  ${filter_options[i]} - ${filter_descriptions[i]}"
            fi
        done
    }
    
    draw_filter_menu
    
    while true; do
        read -rsn1 key
        
        case "$key" in
            $'\033')
                read -rsn2 key
                case "$key" in
                    '[A')
                        if [[ $selected -gt 0 ]]; then
                            selected=$((selected - 1))
                            tput cuu $total
                            draw_filter_menu
                        fi
                        ;;
                    '[B')
                        if [[ $selected -lt $((total - 1)) ]]; then
                            selected=$((selected + 1))
                            tput cuu $total
                            draw_filter_menu
                        fi
                        ;;
                esac
                ;;
            '')
                printf "\033[?25h"
                tput cuu $total
                for i in $(seq 1 $((total + 3))); do
                    tput el
                    echo ""
                done
                tput cuu $((total + 3))
                
                local chosen_filter="${filter_options[selected]}"
                echo -e "${GREEN}Selected: ${chosen_filter}${NC}"
                echo ""
                
                local search_filter=""
                local type_filter=""
                
                case "$chosen_filter" in
                    "Show all records")
                        ;;
                    "Filter by record type")
                        echo "Available record types: A, AAAA, CNAME, MX, TXT, NS, SOA, PTR, SRV, CAA"
                        read -p "Enter record type: " type_filter
                        ;;
                    "Search by name pattern")
                        read -p "Enter name pattern to search: " search_filter
                        ;;
                    "Show only simple records")
                        type_filter="simple"
                        ;;
                esac
                
                break
                ;;
            'q'|'Q')
                printf "\033[?25h"
                echo ""
                echo "Goodbye!"
                return 0
                ;;
        esac
    done
    
    echo ""
    
    local -a records_json
    local jq_filter=".ResourceRecordSets[]"
    
    if [[ "$type_filter" == "simple" ]]; then
        jq_filter=".ResourceRecordSets[] | select(.SetIdentifier == null)"
    elif [[ -n "$type_filter" ]]; then
        jq_filter=".ResourceRecordSets[] | select(.Type == \"$type_filter\")"
    fi
    
    while IFS= read -r record_json; do
        records_json+=("$record_json")
    done < <(jq -c "$jq_filter" "$records_file")
    
    if [[ -n "$search_filter" ]]; then
        local -a filtered_records
        for record_json in "${records_json[@]}"; do
            local name=$(echo "$record_json" | jq -r '.Name')
            if [[ "$name" == *"$search_filter"* ]]; then
                filtered_records+=("$record_json")
            fi
        done
        records_json=("${filtered_records[@]}")
    fi
    
    if [[ ${#records_json[@]} -eq 0 ]]; then
        echo -e "${RED}No records found matching the criteria${NC}"
        return 1
    fi
    
    local -a records_display
    local -a records_data_raw
    
    for i in "${!records_json[@]}"; do
        local record_json="${records_json[i]}"
        local name=$(echo "$record_json" | jq -r '.Name')
        local type=$(echo "$record_json" | jq -r '.Type')
        local set_id=$(echo "$record_json" | jq -r '.SetIdentifier // ""')
        local value
        local display_name
        local routing_info=""
        
        if [[ -n "$set_id" ]]; then
            if echo "$record_json" | jq -e '.Weight' > /dev/null; then
                local weight=$(echo "$record_json" | jq -r '.Weight')
                routing_info=" [WEIGHTED:$weight]"
            elif echo "$record_json" | jq -e '.GeoLocation' > /dev/null; then
                routing_info=" [GEO]"
            elif echo "$record_json" | jq -e '.Region' > /dev/null; then
                routing_info=" [LATENCY]"
            elif echo "$record_json" | jq -e '.Failover' > /dev/null; then
                local failover=$(echo "$record_json" | jq -r '.Failover')
                routing_info=" [FAILOVER:$failover]"
            fi
        fi
        
        if echo "$record_json" | jq -e '.ResourceRecords' > /dev/null; then
            value=$(echo "$record_json" | jq -r '.ResourceRecords[0].Value')
            display_name=$(echo "$name" | sed 's/\\052/*/g')
            records_display+=("${display_name%%.} (${type}) -> ${value}${routing_info}")
        else
            value=$(echo "$record_json" | jq -r '.AliasTarget.DNSName')
            display_name=$(echo "$name" | sed 's/\\052/*/g')
            records_display+=("${display_name%%.} (${type}) -> ${value} [ALIAS]${routing_info}")
        fi
        
        records_data_raw+=("$record_json")
    done
    
    local total=${#records_display[@]}
    local selected=0
    
    echo -e "${BLUE}Found ${total} records${NC}"
    echo ""
    echo -e "${BLUE}Select a record to convert (up/down arrows, Enter to select, q to quit):${NC}"
    echo ""
    
    printf "\033[?25l"
    
    draw_menu() {
        for i in "${!records_display[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}> ${records_display[i]}${NC}"
            else
                echo -e "  ${records_display[i]}"
            fi
        done
    }
    
    draw_menu
    
    while true; do
        read -rsn1 key
        
        case "$key" in
            $'\033')
                read -rsn2 key
                case "$key" in
                    '[A')
                        if [[ $selected -gt 0 ]]; then
                            selected=$((selected - 1))
                            tput cuu $total
                            draw_menu
                        fi
                        ;;
                    '[B')
                        if [[ $selected -lt $((total - 1)) ]]; then
                            selected=$((selected + 1))
                            tput cuu $total
                            draw_menu
                        fi
                        ;;
                esac
                ;;
            '')
                printf "\033[?25h"
                tput cuu $total
                for i in $(seq 1 $((total + 4))); do
                    tput el
                    echo ""
                done
                tput cuu $((total + 4))
                
                local selected_record="${records_data_raw[selected]}"
                local display_name=$(echo "$selected_record" | jq -r '.Name' | sed 's/\\052/*/g')
                local type=$(echo "$selected_record" | jq -r '.Type')
                local set_id=$(echo "$selected_record" | jq -r '.SetIdentifier // ""')
                
                echo -e "${GREEN}Selected: ${display_name%%.} (${type})${NC}"
                if [[ -n "$set_id" ]]; then
                    echo -e "${YELLOW}Note: This record already has routing policy (SetIdentifier: $set_id)${NC}"
                fi
                echo ""
                
                if [[ "$type" == "A" ]]; then
                    choose_routing_policy "$selected_record"
                else
                    echo -e "${RED}Only A records can be converted to routing policies${NC}"
                    echo "Press any key to continue..."
                    read -rsn1
                    policy_manager
                fi
                return
                ;;
            'q'|'Q')
                printf "\033[?25h"
                echo ""
                echo "Goodbye!"
                return 0
                ;;
        esac
    done
}

choose_routing_policy() {
    local record_json="$1"
    
    local routing_policies=("Weighted" "Geolocation")
    local policy_descriptions=(
        "Route traffic based on assigned weights"
        "Route traffic based on geographic location"
    )
    
    local total=${#routing_policies[@]}
    local selected=0
    
    echo -e "${BLUE}Choose new routing policy (up/down arrows, Enter to select, q to quit):${NC}"
    echo ""
    
    printf "\033[?25l"
    
    draw_routing_menu() {
        for i in "${!routing_policies[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}> ${routing_policies[i]}${NC} - ${policy_descriptions[i]}"
            else
                echo -e "  ${routing_policies[i]} - ${policy_descriptions[i]}"
            fi
        done
    }
    
    draw_routing_menu
    
    while true; do
        read -rsn1 key
        
        case "$key" in
            $'\033')
                read -rsn2 key
                case "$key" in
                    '[A')
                        if [[ $selected -gt 0 ]]; then
                            selected=$((selected - 1))
                            tput cuu $total
                            draw_routing_menu
                        fi
                        ;;
                    '[B')
                        if [[ $selected -lt $((total - 1)) ]]; then
                            selected=$((selected + 1))
                            tput cuu $total
                            draw_routing_menu
                        fi
                        ;;
                esac
                ;;
            '')
                printf "\033[?25h"
                tput cuu $total
                for i in $(seq 1 $((total + 3))); do
                    tput el
                    echo ""
                done
                tput cuu $((total + 3))
                
                local chosen_policy="${routing_policies[selected]}"
                echo -e "${GREEN}Selected: ${chosen_policy}${NC}"
                echo ""
                
                case "$chosen_policy" in
                    "Weighted")
                        configure_weighted "$record_json"
                        ;;
                    "Geolocation")
                        configure_geolocation "$record_json"
                        ;;
                esac
                return
                ;;
            'q'|'Q')
                printf "\033[?25h"
                echo ""
                echo "Cancelled"
                return 0
                ;;
        esac
    done
}

configure_weighted() {
    local record_json="$1"
    local name=$(echo "$record_json" | jq -r '.Name')
    local type=$(echo "$record_json" | jq -r '.Type')
    
    echo -e "${BLUE}Configuring Weighted Routing${NC}"
    echo ""
    
    read -p "Enter Set Identifier: " set_id
    if [[ -z "$set_id" ]]; then
        echo -e "${RED}Set Identifier is required${NC}"
        return 1
    fi
    
    read -p "Enter Weight (0-255): " weight
    if [[ ! "$weight" =~ ^[0-9]+$ ]] || [[ "$weight" -gt 255 ]]; then
        echo -e "${RED}Invalid weight${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Converting to weighted routing...${NC}"
    
    local delete_record
    local create_record
    
    if echo "$record_json" | jq -e '.ResourceRecords' > /dev/null; then
        local ttl=$(echo "$record_json" | jq -r '.TTL // 300')
        read -p "Enter TTL (default $ttl): " new_ttl
        new_ttl=${new_ttl:-$ttl}
        
        delete_record=$(echo "$record_json" | jq 'del(.SetIdentifier, .Weight, .Region, .GeoLocation, .Failover)')
        
        create_record=$(echo "$record_json" | jq --arg set_id "$set_id" --argjson weight "$weight" --argjson ttl "$new_ttl" '
            .SetIdentifier = $set_id |
            .Weight = $weight |
            .TTL = $ttl |
            del(.Region, .GeoLocation, .Failover)')
    else
        delete_record=$(echo "$record_json" | jq 'del(.SetIdentifier, .Weight, .Region, .GeoLocation, .Failover)')
        
        create_record=$(echo "$record_json" | jq --arg set_id "$set_id" --argjson weight "$weight" '
            .SetIdentifier = $set_id |
            .Weight = $weight |
            del(.TTL, .Region, .GeoLocation, .Failover)')
    fi
    
    local change_batch="{\"Changes\":[
        {\"Action\":\"DELETE\",\"ResourceRecordSet\":$delete_record},
        {\"Action\":\"CREATE\",\"ResourceRecordSet\":$create_record}
    ]}"
    
    apply_changes "$change_batch"
}

configure_geolocation() {
    local record_json="$1"
    local name=$(echo "$record_json" | jq -r '.Name')
    local type=$(echo "$record_json" | jq -r '.Type')
    
    echo -e "${BLUE}Configuring Geolocation Routing${NC}"
    echo ""
    
    read -p "Enter Set Identifier: " set_id
    if [[ -z "$set_id" ]]; then
        echo -e "${RED}Set Identifier is required${NC}"
        return 1
    fi
    
    echo "Select location:"
    echo "1. NA (North America)"
    echo "2. EU (Europe)"
    echo "3. AS (Asia)"
    echo "4. AF (Africa)"
    echo "5. OC (Oceania)"
    echo "6. SA (South America)"
    echo "7. Custom country code"
    
    read -p "Choose (1-7): " loc_choice
    
    local geo_location=""
    case "$loc_choice" in
        1) geo_location='{"ContinentCode":"NA"}' ;;
        2) geo_location='{"ContinentCode":"EU"}' ;;
        3) geo_location='{"ContinentCode":"AS"}' ;;
        4) geo_location='{"ContinentCode":"AF"}' ;;
        5) geo_location='{"ContinentCode":"OC"}' ;;
        6) geo_location='{"ContinentCode":"SA"}' ;;
        7)
            read -p "Enter country code (e.g. KR, JP, US): " country
            geo_location="{\"CountryCode\":\"$country\"}"
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            return 1
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}Converting to geolocation routing...${NC}"
    
    local delete_record
    local create_record
    
    if echo "$record_json" | jq -e '.ResourceRecords' > /dev/null; then
        local ttl=$(echo "$record_json" | jq -r '.TTL // 300')
        read -p "Enter TTL (default $ttl): " new_ttl
        new_ttl=${new_ttl:-$ttl}
        
        delete_record=$(echo "$record_json" | jq 'del(.SetIdentifier, .Weight, .Region, .GeoLocation, .Failover)')
        
        create_record=$(echo "$record_json" | jq --arg set_id "$set_id" --argjson ttl "$new_ttl" --argjson geo_location "$geo_location" '
            .SetIdentifier = $set_id |
            .TTL = $ttl |
            .GeoLocation = $geo_location |
            del(.Weight, .Region, .Failover)')
    else
        delete_record=$(echo "$record_json" | jq 'del(.SetIdentifier, .Weight, .Region, .GeoLocation, .Failover)')
        
        create_record=$(echo "$record_json" | jq --arg set_id "$set_id" --argjson geo_location "$geo_location" '
            .SetIdentifier = $set_id |
            .GeoLocation = $geo_location |
            del(.TTL, .Weight, .Region, .Failover)')
    fi
    
    local change_batch="{\"Changes\":[
        {\"Action\":\"DELETE\",\"ResourceRecordSet\":$delete_record},
        {\"Action\":\"CREATE\",\"ResourceRecordSet\":$create_record}
    ]}"
    
    apply_changes "$change_batch"
}

configure_latency() {
    local record_json="$1"
    local name=$(echo "$record_json" | jq -r '.Name')
    local type=$(echo "$record_json" | jq -r '.Type')
    
    echo -e "${BLUE}Configuring Latency Routing${NC}"
    echo ""
    
    read -p "Enter Set Identifier: " set_id
    if [[ -z "$set_id" ]]; then
        echo -e "${RED}Set Identifier is required${NC}"
        return 1
    fi
    
    echo "Select AWS Region:"
    echo "1. us-east-1"
    echo "2. us-west-2"
    echo "3. eu-west-1"
    echo "4. ap-northeast-1"
    echo "5. ap-northeast-2"
    echo "6. ap-southeast-1"
    
    read -p "Choose (1-6): " region_choice
    
    local region=""
    case "$region_choice" in
        1) region="us-east-1" ;;
        2) region="us-west-2" ;;
        3) region="eu-west-1" ;;
        4) region="ap-northeast-1" ;;
        5) region="ap-northeast-2" ;;
        6) region="ap-southeast-1" ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            return 1
            ;;
    esac
    
    read -p "Enter TTL (default 300): " ttl
    ttl=${ttl:-300}
    
    echo ""
    echo -e "${CYAN}Converting to latency routing...${NC}"
    
    local change_batch="{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$name\",\"Type\":\"$type\",\"SetIdentifier\":\"$set_id\",\"Region\":\"$region\",\"TTL\":$ttl,\"ResourceRecords\":[{\"Value\":\"$value\"}]}}]}"
    
    apply_changes "$change_batch"
}

configure_failover() {
    local record_json="$1"
    local name=$(echo "$record_json" | jq -r '.Name')
    local type=$(echo "$record_json" | jq -r '.Type')
    
    echo -e "${BLUE}Configuring Failover Routing${NC}"
    echo ""
    
    read -p "Enter Set Identifier: " set_id
    if [[ -z "$set_id" ]]; then
        echo -e "${RED}Set Identifier is required${NC}"
        return 1
    fi
    
    echo "Choose failover type:"
    echo "1. PRIMARY"
    echo "2. SECONDARY"
    
    read -p "Choose (1-2): " failover_choice
    
    local failover_type=""
    case "$failover_choice" in
        1) failover_type="PRIMARY" ;;
        2) failover_type="SECONDARY" ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            return 1
            ;;
    esac
    
    read -p "Enter TTL (default 300): " ttl
    ttl=${ttl:-300}
    
    echo ""
    echo -e "${CYAN}Converting to failover routing...${NC}"
    
    local change_batch="{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$name\",\"Type\":\"$type\",\"SetIdentifier\":\"$set_id\",\"Failover\":\"$failover_type\",\"TTL\":$ttl,\"ResourceRecords\":[{\"Value\":\"$value\"}]}}]}"
    
    apply_changes "$change_batch"
}

apply_changes() {
    local change_batch="$1"
    
    echo -e "${CYAN}Applying changes to AWS...${NC}"
    
    local change_id
    local error_output
    if change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --profile "$PROFILE" \
        --change-batch "$change_batch" \
        --query 'ChangeInfo.Id' \
        --output text 2>&1); then
        
        echo -e "${GREEN}Change submitted successfully (ID: ${change_id})${NC}"
        echo ""
        echo -e "${GREEN}Routing type conversion completed!${NC}"
        
    else
        echo -e "${RED}Failed to apply changes${NC}"
        echo -e "${RED}Error: ${change_id}${NC}"
    fi
    
    echo ""
}

manage_policies() {
    if ! load_config; then
        echo -e "${RED}No configuration found${NC}"
        echo "Please run: r53 config [hosted-zone-id] [aws-profile]"
        exit 1
    fi
    
    check_dependencies
    
    echo -e "${BLUE}Route 53 Policy Manager${NC}"
    echo -e "${BLUE}=======================${NC}"
    echo "Hosted Zone: $HOSTED_ZONE_ID"
    echo "AWS Profile: $PROFILE"
    echo ""
    
    load_all_records
    policy_manager
}