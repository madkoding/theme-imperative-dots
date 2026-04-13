#!/usr/bin/env bash

# ============================================================================
# 1. ZOMBIE PREVENTION
# Kills any older instances of this script. When Quickshell reloads,
# it can leave the old listener pipelines running in the background infinitely.
# ============================================================================
for pid in $(pgrep -f "quickshell/workspaces.sh"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

# Cleanly kill immediate children (like socat) when the script exits normally
cleanup() {
    pkill -P $$ 2>/dev/null
}
trap cleanup EXIT SIGTERM SIGINT

# --- Special Cleanup for Network/Bluetooth ---
# The network toggle starts a background bluetooth scan that must be killed explicitly.
BT_PID_FILE="$HOME/.cache/bt_scan_pid"

if [ -f "$BT_PID_FILE" ]; then
    kill $(cat "$BT_PID_FILE") 2>/dev/null
    rm -f "$BT_PID_FILE"
fi

# Ensure bluetooth scan is explicitly turned off (timeout prevents deadlocks on fresh installs)
(timeout 2 bluetoothctl scan off > /dev/null 2>&1) &
# ---------------------------------------------

# Configuration: How many workspaces do you want to show?
SEQ_END=6

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
QS_STATE_DIR="${RUNTIME_DIR}/mados-quickshell"
ACTIVE_WIDGET_FILE="${QS_ACTIVE_WIDGET_FILE:-${QS_STATE_DIR}/qs_active_widget}"
LEGACY_ACTIVE_WIDGET_FILE="/tmp/qs_active_widget"

get_active_workspace_id() {
    timeout 2 hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty'
}

is_master_window_open() {
    timeout 2 hyprctl clients -j 2>/dev/null | jq -e '
        any(.[];
            (.title // "") == "qs-master" and
            ((.size[0] // 1) > 1) and
            ((.size[1] // 1) > 1)
        )
    ' >/dev/null 2>&1
}

print_workspaces() {
    # Get raw data with a timeout fallback
    spaces=$(timeout 2 hyprctl workspaces -j 2>/dev/null)
    active=$(timeout 2 hyprctl activeworkspace -j 2>/dev/null | jq '.id')

    # Failsafe if hyprctl crashes to prevent jq from outputting errors
    if [ -z "$spaces" ] || [ -z "$active" ]; then return; fi

    # Generate the JSON and write it atomically to prevent UI flickering
    echo "$spaces" | jq --unbuffered --argjson a "$active" --arg end "$SEQ_END" -c '
        # Create a map of workspace ID -> workspace data for easy lookup
        (map( { (.id|tostring): . } ) | add) as $s
        |
        # Iterate from 1 to SEQ_END
        [range(1; ($end|tonumber) + 1)] | map(
            . as $i |
            # Determine state: active -> occupied -> empty
            (if $i == $a then "active"
             elif ($s[$i|tostring] != null and $s[$i|tostring].windows > 0) then "occupied"
             else "empty" end) as $state |

            # Get window title for tooltip (if exists)
            (if $s[$i|tostring] != null then $s[$i|tostring].lastwindowtitle else "Empty" end) as $win |

            {
                id: $i,
                state: $state,
                tooltip: $win
            }
        )
    ' > /tmp/qs_workspaces.tmp

    mv /tmp/qs_workspaces.tmp /tmp/qs_workspaces.json
}

# Print initial state
print_workspaces
last_active_ws="$(get_active_workspace_id)"

# ============================================================================
# 2. THE EVENT DEBOUNCER
# Listen to Hyprland socket wrapped in an infinite loop
# ============================================================================
while true; do
    while read -r line; do
        case "$line" in
            workspace*|focusedmon*|destroyworkspace*)

                # -> THE FIX <-
                # Hyprland emits HUNDREDS of events a second when you move/resize windows.
                # This reads and discards all subsequent events arriving within a 50ms window.
                # It bundles the storm into a single UI update, completely preventing CPU clogging!
                while read -t 0.05 -r extra_line; do
                    continue
                done

                print_workspaces

                new_active_ws="$(get_active_workspace_id)"
                if [ -n "$new_active_ws" ]; then
                    if [ -n "$last_active_ws" ] && [ "$new_active_ws" != "$last_active_ws" ]; then
                        if is_master_window_open; then
                            ~/.config/hypr/scripts/qs_manager.sh close all keepfocus instant >/dev/null 2>&1 &
                        fi
                    fi
                    last_active_ws="$new_active_ws"
                fi
                ;;
        esac
    done < <(socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock -)
    sleep 1
done
