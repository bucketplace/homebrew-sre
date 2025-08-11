#!/bin/bash

# lib/common.sh - Common helpers for akamaistg

check_dependency() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}❌ '$cmd' not found${NC}"
        [ -n "$hint" ] && echo -e "${YELLOW}💡 Install with: $hint${NC}"
        return 1
    fi
}

ensure_tools() {
    check_dependency "curl" "brew install curl" || return 1
}

print_section() {
    echo -e "${YELLOW}=== $* ===${NC}"
}

print_kv() {
    local k="$1"; shift
    local v="$*"
    printf "%-22b %b\n" "$k:" "$v"
}


