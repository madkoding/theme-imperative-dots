#!/usr/bin/env bash

nmcli_wifi_state() {
    local raw
    raw="$(LC_ALL=C nmcli radio wifi 2>/dev/null | tr '[:upper:]' '[:lower:]' | xargs)"
    if [[ "$raw" == "enabled" ]]; then
        echo "on"
    else
        echo "off"
    fi
}

toggle_power() {
    local current target
    current="$(nmcli_wifi_state)"
    if [[ "$current" == "on" ]]; then
        target="off"
        nmcli radio wifi off >/dev/null 2>&1 || true
    else
        target="on"
        rfkill unblock wifi >/dev/null 2>&1 || true
        nmcli radio wifi on >/dev/null 2>&1 || true
    fi

    for _ in {1..20}; do
        if [[ "$(nmcli_wifi_state)" == "$target" ]]; then
            break
        fi
        sleep 0.2
    done
}

emit_status() {
    local POWER
    POWER="$(nmcli_wifi_state)"

    if [[ "$POWER" == "off" ]]; then
        echo '{ "power": "off", "connected": null, "networks": [] }'
        return
    fi

# Function to get icon based on signal strength
get_icon() {
    local signal=$1
    if [[ $signal -ge 80 ]]; then echo "󰤨";
    elif [[ $signal -ge 60 ]]; then echo "󰤥";
    elif [[ $signal -ge 40 ]]; then echo "󰤢";
    elif [[ $signal -ge 20 ]]; then echo "󰤟";
    else echo "󰤯"; fi
}

CACHE_DIR="/tmp/quickshell_network_cache"
mkdir -p "$CACHE_DIR"

# Get current connection details
CURRENT_RAW=$(LC_ALL=C nmcli -t -f active,ssid,signal,security device wifi 2>/dev/null | grep "^yes")

if [[ -n "$CURRENT_RAW" ]]; then
    IFS=':' read -r active ssid signal security <<< "$CURRENT_RAW"
    icon=$(get_icon "$signal")
    
    # Safe filename for cache
    SAFE_SSID="${ssid//[^a-zA-Z0-9]/_}"
    CACHE_FILE="$CACHE_DIR/wifi_$SAFE_SSID"
    
    # Load cached IP and FREQ if they exist to prevent blocking
    if [ -f "$CACHE_FILE" ]; then
        source "$CACHE_FILE"
    fi
    
    # If cache is missing, fetch the expensive stats once and save them
    if [ -z "$IP" ] || [ "$IP" == "No IP" ] || [ -z "$FREQ" ]; then
        IFACE=$(LC_ALL=C nmcli -t -f DEVICE,TYPE d 2>/dev/null | awk -F: '$2=="wifi"{print $1;exit}')
        IP=$(ip -4 addr show dev "$IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
        [ -z "$IP" ] && IP="No IP"
        
        FREQ=$(iw dev "$IFACE" link 2>/dev/null | grep freq | awk '{print $2}')
        [ -n "$FREQ" ] && FREQ="${FREQ} MHz" || FREQ="Unknown"
        
        echo "IP=\"$IP\"" > "$CACHE_FILE"
        echo "FREQ=\"$FREQ\"" >> "$CACHE_FILE"
    fi

    CONNECTED_JSON=$(jq -n \
                  --arg id "$ssid" \
                  --arg ssid "$ssid" \
                  --arg icon "$icon" \
                  --arg signal "$signal" \
                  --arg security "$security" \
                  --arg ip "$IP" \
                  --arg freq "$FREQ" \
                  '{id: $id, ssid: $ssid, icon: $icon, signal: $signal, security: $security, ip: $ip, freq: $freq}')
else
    CONNECTED_JSON="null"
fi

# Get available networks INSTANTLY using --rescan no
NETWORKS_JSON=$(LC_ALL=C nmcli -t -f active,ssid,signal,security device wifi list --rescan no 2>/dev/null | \
    awk -F: '!seen[$2]++ && $2 != "" && $1 != "yes" {print $2":"$3":"$4}' | \
    head -n 24 | \
    while IFS=':' read -r ssid signal security; do
        icon=$(get_icon "$signal")
        jq -n \
           --arg id "$ssid" \
           --arg ssid "$ssid" \
           --arg icon "$icon" \
           --arg signal "$signal" \
           --arg security "$security" \
           '{id: $id, ssid: $ssid, icon: $icon, signal: $signal, security: $security}'
    done | jq -s '.')

echo $(jq -n \
       --arg power "on" \
       --argjson connected "${CONNECTED_JSON:-null}" \
       --argjson networks "${NETWORKS_JSON:-[]}" \
       '{power: $power, connected: $connected, networks: $networks}')
}

case "$1" in
    --toggle)
        toggle_power
        ;;
esac

emit_status
