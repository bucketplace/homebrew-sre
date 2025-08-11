#!/bin/bash

# lib/testall.sh - Batch testing from YAML targets

# shellcheck disable=SC1091
[ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/lib/test.sh" ] && source "$SCRIPT_DIR/lib/test.sh"

run_test_all() {
    # Optional first arg is mode (stg|prod); optional second is yaml path
    local mode_param=""
    local targets_file=""

    if [ "$#" -ge 1 ] && { [ "$1" = "stg" ] || [ "$1" = "prod" ]; }; then
        mode_param="$1"
        shift
    fi

    if [ "$#" -ge 1 ]; then
        targets_file="$1"
    fi

    targets_file="${targets_file:-${AKAMAISTG_TARGETS:-${AKAMAISTG_TARGETS_YAML:-./akamaistg_targets.yaml}}}"

    if [ ! -f "$targets_file" ]; then
        echo -e "${RED}✗ Targets YAML not found: $targets_file${NC}" >&2
        echo -e "${YELLOW}💡 Create YAML in the form:${NC}" >&2
        echo "hosts:" >&2
        echo "  example.com:" >&2
        echo "    - /" >&2
        echo "    - /health" >&2
        return 1
    fi

    # Derive display mode for header
    local display_mode
    if [ -n "$mode_param" ]; then
        display_mode="$mode_param"
    else
        display_mode=$(echo "${AKAMAISTG_ENV:-staging}" | tr '[:upper:]' '[:lower:]')
    fi
    print_section "Running ${display_mode} tests from YAML: $targets_file"
    local total=0 ok=0 fail=0
    local current_host=""

    while IFS= read -r raw || [ -n "$raw" ]; do
        # strip comments and trailing spaces
        local line
        line=$(echo "$raw" | sed 's/#.*$//' | sed 's/[[:space:]]*$//')
        # skip empty
        echo "$line" | grep -E '^[[:space:]]*$' >/dev/null && continue

        # host header line: e.g., "  example.com:"
        if echo "$line" | grep -Eq '^[[:space:]]*[A-Za-z0-9.-]+:[[:space:]]*$'; then
            local name
            name=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/:[[:space:]]*$//')
            # ignore top-level keys like hosts/targets
            case "$name" in
                hosts|targets) current_host="" ; continue ;;
                *) current_host="$name" ;;
            esac
            continue
        fi

        # path item line: e.g., "    - /path"
        if echo "$line" | grep -Eq '^[[:space:]]*-[[:space:]]*/'; then
            if [ -z "$current_host" ]; then
                continue
            fi
            local path
            path=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//')
            # ensure leading slash
            [[ "$path" != /* ]] && path="/$path"

            total=$((total + 1))
            echo -e "${GRAY}→ Testing: ${current_host} ${path}${NC}"
            if [ -n "$mode_param" ]; then
                run_test "$current_host" "$path" "$mode_param"
            else
                run_test "$current_host" "$path"
            fi
            local rc=$?
            if [ $rc -eq 0 ]; then
                ok=$((ok + 1))
            else
                fail=$((fail + 1))
            fi
            echo
            continue
        fi
    done < "$targets_file"

    print_section "Summary"
    print_kv "Total" "$total"
    print_kv "Success" "$ok"
    if [ "$fail" -gt 0 ]; then
        print_kv "Failed" "${RED}${fail}${NC}"
        return 2
    else
        print_kv "Failed" "0"
    fi
}


