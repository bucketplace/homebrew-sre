#!/bin/bash

load_records() {
    local records_file="$TEMP_DIR/records.json"
    
    echo -e "${CYAN}Loading records from Route 53...${NC}"
    
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --profile "$PROFILE" \
        --output json > "$records_file"
    
    echo -e "${GREEN}✓ Records loaded${NC}"
    echo ""
}

weight_manager() {
    local records_file="$TEMP_DIR/records.json"
    
    local records_data
    records_data=$(jq -r '.ResourceRecordSets[] | select(.SetIdentifier != null) | 
        [(.Name // ""), (.Type // ""), (.SetIdentifier // ""), (.Weight // 0), 
         (if .ResourceRecords then .ResourceRecords[0].Value else .AliasTarget.DNSName end)] | 
        @tsv' "$records_file")
    
    if [[ -z "$records_data" ]]; then
        echo -e "${RED}No weighted records found in this hosted zone${NC}"
        return 1
    fi
    
    local -a records_display
    local -a records_data_raw
    while IFS=$'\t' read -r name type set_id weight value; do
        local display_name=$(echo "$name" | sed 's/\\052/*/g')
        records_display+=("${display_name%%.} (${type}) - ${set_id} [Weight: ${weight}] -> ${value}")
        records_data_raw+=("$name|$type|$set_id|$weight")
    done <<< "$records_data"
    
    local total=${#records_display[@]}
    local selected=0
    
    echo -e "${BLUE}Found ${total} weighted records${NC}"
    echo ""
    echo -e "${BLUE}Select a record to change weight (↑/↓ to navigate, Enter to select, q to quit):${NC}"
    echo ""
    
    printf "\033[?25l"
    
    draw_menu() {
        for i in "${!records_display[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}► ${records_display[i]}${NC}"
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
                
                IFS='|' read -r sel_name sel_type sel_set_id sel_weight <<< "${records_data_raw[selected]}"
                
                local display_name=$(echo "$sel_name" | sed 's/\\052/*/g')
                echo -e "${GREEN}Selected: ${display_name%%.} (${sel_type}) - ${sel_set_id}${NC}"
                echo ""
                
                change_weight "$sel_name" "$sel_type" "$sel_set_id" "$sel_weight" "$records_file"
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

change_weight() {
    local name="$1"
    local type="$2"
    local set_id="$3"
    local current_weight="$4"
    local records_file="$5"
    
    echo -e "${BLUE}Current weight: ${YELLOW}${current_weight}${NC}"
    echo ""
    
    read -p "Enter new weight (0-255) [Enter to cancel]: " new_weight
    
    if [[ -z "$new_weight" ]]; then
        echo -e "${YELLOW}Weight change cancelled${NC}"
        restart_weight_manager
        return
    fi
    
    if [[ ! "$new_weight" =~ ^[0-9]+$ ]] || [[ "$new_weight" -gt 255 ]] || [[ "$new_weight" -lt 0 ]]; then
        echo -e "${RED}Invalid weight. Must be 0-255${NC}"
        echo ""
        restart_weight_manager
        return
    fi
    
    if [[ "$new_weight" == "$current_weight" ]]; then
        echo -e "${YELLOW}Weight unchanged (${current_weight})${NC}"
        echo ""
        restart_weight_manager
        return
    fi
    
    echo -e "${CYAN}Changing weight: ${current_weight} → ${new_weight}${NC}"
    echo ""
    
    local record_json
    record_json=$(jq ".ResourceRecordSets[] | select(.Name == \"$name\" and .Type == \"$type\" and .SetIdentifier == \"$set_id\")" "$records_file")
    
    local updated_record
    updated_record=$(echo "$record_json" | jq ".Weight = $new_weight")
    
    local change_batch
    change_batch=$(cat << EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": $updated_record
  }]
}
EOF
)
    
    echo -e "${CYAN}Applying changes to AWS...${NC}"
    
    local change_id
    if change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --profile "$PROFILE" \
        --change-batch "$change_batch" \
        --query 'ChangeInfo.Id' \
        --output text 2>/dev/null); then
        
        echo -e "${GREEN}✓ Change submitted (ID: ${change_id})${NC}"
        echo ""
        echo -e "${GREEN}Weight successfully changed!${NC}"
        echo -e "${BLUE}$(echo "$name" | sed 's/\\052/*/g') (${type}) - ${set_id}: ${current_weight} → ${GREEN}${new_weight}${NC}"
        
    else
        echo -e "${RED}✗ Failed to apply changes${NC}"
        echo "Please check your AWS credentials and permissions."
    fi
    
    echo ""
    restart_weight_manager
}

restart_weight_manager() {
    echo -e "${CYAN}Loading latest records...${NC}"
    load_records
    weight_manager
}

manage_weights() {
    if [[ -n "${1:-}" && -n "${2:-}" ]]; then
        local hosted_zone_id="$1"
        local profile="$2"
        
        if ! validate_profile "$profile"; then
            echo -e "${RED}✗ AWS profile '$profile' not found${NC}"
            echo "Available profiles:"
            aws configure list-profiles 2>/dev/null || echo "No profiles configured"
            exit 1
        fi
        
        if ! validate_hosted_zone "$hosted_zone_id" "$profile"; then
            echo -e "${RED}✗ Hosted zone '$hosted_zone_id' not accessible with profile '$profile'${NC}"
            echo "Please check the hosted zone ID and AWS permissions"
            exit 1
        fi
        
        save_config "$hosted_zone_id" "$profile"
        
        HOSTED_ZONE_ID="$hosted_zone_id"
        PROFILE="$profile"
        
        echo -e "${GREEN}✓ Configuration saved${NC}"
        echo "Hosted Zone: $hosted_zone_id"
        echo "AWS Profile: $profile"
        echo ""
        
    else
        if ! load_config; then
            echo -e "${RED}✗ No configuration found${NC}"
            echo "Usage: r53 weight <hosted-zone-id> <aws-profile>"
            exit 1
        fi
        
        echo -e "${GREEN}Using saved configuration:${NC}"
        echo "Hosted Zone: $HOSTED_ZONE_ID"
        echo "AWS Profile: $PROFILE"
        echo ""
    fi
    
    check_dependencies
    
    echo -e "${BLUE}Route 53 Weight Manager${NC}"
    echo -e "${BLUE}=======================${NC}"
    echo ""
    
    load_records
    weight_manager
}