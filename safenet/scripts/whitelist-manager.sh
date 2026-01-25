#!/bin/bash
# =============================================================================
# OSS DNS Whitelist Manager
# =============================================================================
# Purpose: Easy tool for adding/removing domains from whitelist
# Location: /opt/oss-blocklists/scripts/whitelist-manager.sh
#
# Usage:
#   ./whitelist-manager.sh add <domain>     - Add domain to whitelist
#   ./whitelist-manager.sh remove <domain>  - Remove domain from whitelist
#   ./whitelist-manager.sh list             - Show all whitelisted domains
#   ./whitelist-manager.sh search <domain>  - Check if domain is whitelisted
#
# After changes, run update-dns-blocklist.sh to regenerate the combined list.
# =============================================================================

WHITELIST_FILE="/opt/oss-blocklists/output/dns/whitelist.txt"

show_help() {
    echo "OSS DNS Whitelist Manager"
    echo ""
    echo "Usage:"
    echo "  ./whitelist-manager.sh add <domain>     - Add domain to whitelist"
    echo "  ./whitelist-manager.sh remove <domain>  - Remove domain from whitelist"
    echo "  ./whitelist-manager.sh list             - Show all whitelisted domains"
    echo "  ./whitelist-manager.sh search <domain>  - Check if domain is whitelisted"
    echo ""
}

add_domain() {
    domain="$1"
    if grep -q "^${domain}$" "$WHITELIST_FILE" 2>/dev/null; then
        echo "✓ $domain is already whitelisted"
    else
        echo "$domain" >> "$WHITELIST_FILE"
        echo "✓ Added $domain to whitelist"
        echo "  Run update-dns-blocklist.sh to apply changes"
    fi
}

remove_domain() {
    domain="$1"
    if grep -q "^${domain}$" "$WHITELIST_FILE" 2>/dev/null; then
        sed -i "/^${domain}$/d" "$WHITELIST_FILE"
        echo "✓ Removed $domain from whitelist"
        echo "  Run update-dns-blocklist.sh to apply changes"
    else
        echo "✗ $domain is not in whitelist"
    fi
}

list_domains() {
    echo "=== OSS DNS Whitelist ==="
    grep -v "^#" "$WHITELIST_FILE" | grep -v "^$" | sort
    echo ""
    count=$(grep -v "^#" "$WHITELIST_FILE" | grep -v "^$" | wc -l)
    echo "Total: $count domains"
}

search_domain() {
    domain="$1"
    if grep -q "^${domain}$" "$WHITELIST_FILE" 2>/dev/null; then
        echo "✓ $domain IS whitelisted"
    else
        echo "✗ $domain is NOT whitelisted"
    fi
}

# Main logic
case "$1" in
    add)
        if [[ -z "$2" ]]; then
            echo "Error: Please specify a domain"
            echo "Example: ./whitelist-manager.sh add example.com"
            exit 1
        fi
        add_domain "$2"
        ;;
    remove)
        if [[ -z "$2" ]]; then
            echo "Error: Please specify a domain"
            echo "Example: ./whitelist-manager.sh remove example.com"
            exit 1
        fi
        remove_domain "$2"
        ;;
    list)
        list_domains
        ;;
    search)
        if [[ -z "$2" ]]; then
            echo "Error: Please specify a domain"
            echo "Example: ./whitelist-manager.sh search example.com"
            exit 1
        fi
        search_domain "$2"
        ;;
    *)
        show_help
        ;;
esac
