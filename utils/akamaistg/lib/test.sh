#!/bin/bash

# lib/test.sh - Single test commands (staging/prod)

run_test() {
    # Optional trailing param may be mode (stg|prod)
    local args=("$@")
    local mode_param=""
    if [ ${#args[@]} -gt 0 ]; then
        local last="${args[${#args[@]}-1]}"
        if [ "$last" = "stg" ] || [ "$last" = "prod" ]; then
            mode_param="$last"
            unset 'args[${#args[@]}-1]'
            # re-pack to avoid sparse array
            local repacked=()
            local a
            for a in "${args[@]}"; do repacked+=("$a"); done
            args=("${repacked[@]}")
        fi
    fi

    # Mode resolution: CLI trailing param > env > default
    local env_mode
    if [ -n "$mode_param" ]; then
        env_mode="$mode_param"
    else
        env_mode=$(echo "${AKAMAISTG_ENV:-staging}" | tr '[:upper:]' '[:lower:]')
    fi
    case "$env_mode" in
        prod|production)
            run_production_test "${args[@]}"
            ;;
        * )
            run_staging_test "${args[@]}"
            ;;
    esac
}

# Staging test: resolve staging edge and send request
run_staging_test() {
    local first="$1"
    local second="$2"

    if [ -z "$first" ]; then
        echo -e "${RED}✗ Usage: akamaistg test <url> | <host> [path]${NC}" >&2
        return 1
    fi

    ensure_tools || return 1

    local url
    local host
    if [[ "$first" == http://* || "$first" == https://* ]]; then
        url="$first"
        # extract host from URL
        local without_scheme="${url#*://}"
        host="${without_scheme%%/*}"
    else
        host="$first"
        local path="${second:-/}"
        [[ "$path" != /* ]] && path="/$path"
        url="https://$host$path"
    fi

    echo -e "${BLUE}Testing Akamai staging for${NC} ${CYAN}$url${NC}"
    if [ -n "$AKAMAISTG_RESOLVE" ]; then
        echo -e "${GRAY}(using --resolve $AKAMAISTG_RESOLVE)${NC}"
    fi
    echo

    # Determine staging resolve target (required for staging test)
    local resolve_value=""
    if [ -n "$AKAMAISTG_RESOLVE" ]; then
        resolve_value="$AKAMAISTG_RESOLVE"
    else
        check_dependency "dig" "brew install bind" || return 1
        local staging_fqdn
        if [ -n "$AKAMAISTG_STAGING_FQDN" ]; then
            staging_fqdn="${AKAMAISTG_STAGING_FQDN//\{host\}/$host}"
        elif [ -n "$AKAMAISTG_STAGING_SUFFIX" ]; then
            staging_fqdn="${host}.${AKAMAISTG_STAGING_SUFFIX}"
        else
            # Default heuristic: try common Akamai staging pattern
            staging_fqdn="${host}.edgesuite-staging.net"
        fi
        local staging_ips
        staging_ips=$(dig +short A "$staging_fqdn" | grep -E '^[0-9.]+$')
        if [ -z "$staging_ips" ]; then
            # If we used the default heuristic and it failed, give guidance
            if [ -z "$AKAMAISTG_STAGING_FQDN" ] && [ -z "$AKAMAISTG_STAGING_SUFFIX" ]; then
                echo -e "${RED}✗ Could not resolve default staging FQDN: $staging_fqdn${NC}" >&2
                echo -e "${YELLOW}💡 Set AKAMAISTG_STAGING_FQDN (e.g. '{host}.edgesuite-staging.net') or AKAMAISTG_STAGING_SUFFIX (e.g. 'edgesuite-staging.net'), or provide AKAMAISTG_RESOLVE.${NC}" >&2
            else
                echo -e "${RED}❌ No A records found for $staging_fqdn${NC}"
            fi
            return 1
        fi
        local first_ip
        first_ip=$(echo "$staging_ips" | head -n1)
        resolve_value="$host:443:$first_ip"
        echo -e "${CYAN}Forcing staging edge via --resolve ${resolve_value}${NC}"
        echo -e "${GRAY}Staging FQDN: ${staging_fqdn}${NC}"
        echo -e "${GRAY}Staging IP candidates:${NC}"
        echo "$staging_ips" | sed 's/^/  - /'
        echo
    fi

    # Request headers with Akamai debug hints
    local curl_args=(
        -sS
        -D -
        -o /dev/null
        -H "Pragma: akamai-x-cache-on, akamai-x-get-true-cache-key"
        "$url"
    )

    if [ -n "$resolve_value" ]; then
        curl_args=(--resolve "$resolve_value" "${curl_args[@]}")
    fi

    print_section "HTTP Response Headers"
    local headers
    if ! headers=$(curl "${curl_args[@]}"); then
        echo -e "${RED}❌ curl request failed${NC}"
        return 1
    fi

    # Show status with emoji indicator
    local status_line
    status_line=$(echo "$headers" | grep -i '^HTTP/')

    # Parse status code and decorate status line
    local status_code decorated_status
    status_code=$(echo "$status_line" | sed -E 's#HTTP/[0-9.]+[[:space:]]+([0-9]{3}).*#\1#')
    if [ -n "$status_code" ] && [ "$status_code" = "200" ]; then
        decorated_status="${GREEN}✅${NC} $status_line"
    elif [ -n "$status_code" ]; then
        decorated_status="${RED}❌${NC} $status_line"
    else
        decorated_status="$status_line"
    fi
    [ -n "$status_line" ] && print_kv "Status" "$decorated_status"

    # Extract and display common Akamai headers
    local server x_cache x_cache_remote true_cache_key via
    server=$(echo "$headers" | grep -i '^Server:' | head -1 | sed 's/^Server:[[:space:]]*//I')
    x_cache=$(echo "$headers" | grep -i '^X-Cache:' | head -1 | sed 's/^X-Cache:[[:space:]]*//I')
    x_cache_remote=$(echo "$headers" | grep -i '^X-Cache-Remote:' | head -1 | sed 's/^X-Cache-Remote:[[:space:]]*//I')
    true_cache_key=$(echo "$headers" | grep -i '^X-True-Cache-Key:' | head -1 | sed 's/^X-True-Cache-Key:[[:space:]]*//I')
    via=$(echo "$headers" | grep -i '^Via:' | head -1 | sed 's/^Via:[[:space:]]*//I')

    [ -n "$server" ] && print_kv "Server" "$server"
    [ -n "$x_cache" ] && print_kv "X-Cache" "$x_cache"
    [ -n "$x_cache_remote" ] && print_kv "X-Cache-Remote" "$x_cache_remote"
    [ -n "$true_cache_key" ] && print_kv "X-True-Cache-Key" "$true_cache_key"
    [ -n "$via" ] && print_kv "Via" "$via"

    echo
    print_section "Tips"
    echo "- Set AKAMAISTG_RESOLVE=host:443:IP to hit staging edge via curl --resolve"
    echo "- Pragma header enables Akamai debug headers (x-cache, x-true-cache-key)"

    # Exit non-zero on non-200
    if [ -n "$status_code" ] && [ "$status_code" != "200" ]; then
        return 2
    fi
}

# Production test: no forced staging resolution
run_production_test() {
    local first="$1"
    local second="$2"

    if [ -z "$first" ]; then
        echo -e "${RED}✗ Usage: akamaistg prodtest <url> | <host> [path]${NC}" >&2
        return 1
    fi

    ensure_tools || return 1

    local url
    local host
    if [[ "$first" == http://* || "$first" == https://* ]]; then
        url="$first"
        local without_scheme="${url#*://}"
        host="${without_scheme%%/*}"
    else
        host="$first"
        local path="${second:-/}"
        [[ "$path" != /* ]] && path="/$path"
        url="https://$host$path"
    fi

    echo -e "${BLUE}Testing Akamai (production) for${NC} ${CYAN}$url${NC}"
    echo

    local curl_args=(
        -sS
        -D -
        -o /dev/null
        -H "Pragma: akamai-x-cache-on, akamai-x-get-true-cache-key"
        "$url"
    )

    print_section "HTTP Response Headers"
    local headers
    if ! headers=$(curl "${curl_args[@]}"); then
        echo -e "${RED}❌ curl request failed${NC}"
        return 1
    fi

    local status_line
    status_line=$(echo "$headers" | grep -i '^HTTP/')

    # Parse status code and decorate status line
    local status_code decorated_status
    status_code=$(echo "$status_line" | sed -E 's#HTTP/[0-9.]+[[:space:]]+([0-9]{3}).*#\1#')
    if [ -n "$status_code" ] && [ "$status_code" = "200" ]; then
        decorated_status="${GREEN}✅${NC} $status_line"
    elif [ -n "$status_code" ]; then
        decorated_status="${RED}❌${NC} $status_line"
    else
        decorated_status="$status_line"
    fi
    [ -n "$status_line" ] && print_kv "Status" "$decorated_status"

    local server x_cache x_cache_remote true_cache_key via
    server=$(echo "$headers" | grep -i '^Server:' | head -1 | sed 's/^Server:[[:space:]]*//I')
    x_cache=$(echo "$headers" | grep -i '^X-Cache:' | head -1 | sed 's/^X-Cache:[[:space:]]*//I')
    x_cache_remote=$(echo "$headers" | grep -i '^X-Cache-Remote:' | head -1 | sed 's/^X-Cache-Remote:[[:space:]]*//I')
    true_cache_key=$(echo "$headers" | grep -i '^X-True-Cache-Key:' | head -1 | sed 's/^X-True-Cache-Key:[[:space:]]*//I')
    via=$(echo "$headers" | grep -i '^Via:' | head -1 | sed 's/^Via:[[:space:]]*//I')

    [ -n "$server" ] && print_kv "Server" "$server"
    [ -n "$x_cache" ] && print_kv "X-Cache" "$x_cache"
    [ -n "$x_cache_remote" ] && print_kv "X-Cache-Remote" "$x_cache_remote"
    [ -n "$true_cache_key" ] && print_kv "X-True-Cache-Key" "$true_cache_key"
    [ -n "$via" ] && print_kv "Via" "$via"

    # Exit non-zero on non-200
    if [ -n "$status_code" ] && [ "$status_code" != "200" ]; then
        return 2
    fi
}


