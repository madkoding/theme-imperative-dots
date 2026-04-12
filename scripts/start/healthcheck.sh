#!/usr/bin/env bash
set -euo pipefail

QS_ROOT="${HOME}/.config/quickshell"

if [[ ! -f "${QS_ROOT}/widgets/notifications/NotificationPopup.qml" ]]; then
    exit 1
fi

if [[ ! -f "${QS_ROOT}/lib/I18n.qml" ]]; then
    exit 1
fi

if ! pgrep -f "quickshell.*Main.qml" >/dev/null 2>&1; then
    exit 1
fi

if ! pgrep -f "quickshell.*TopBar.qml" >/dev/null 2>&1; then
    exit 1
fi

if [[ "$(pgrep -fc "quickshell.*Main.qml")" -ne 1 ]]; then
    exit 1
fi

if [[ "$(pgrep -fc "quickshell.*TopBar.qml")" -ne 1 ]]; then
    exit 1
fi

if pgrep -af "quickshell.*\.config/hypr/scripts/quickshell/Main\.qml" >/dev/null 2>&1; then
    exit 1
fi

if pgrep -af "quickshell.*\.config/hypr/scripts/quickshell/TopBar\.qml" >/dev/null 2>&1; then
    exit 1
fi

if ! pgrep -af "quickshell.*Main\.qml" | grep -F "${QS_ROOT}/Main.qml" >/dev/null 2>&1; then
    exit 1
fi

if ! pgrep -af "quickshell.*TopBar\.qml" | grep -F "${QS_ROOT}/TopBar.qml" >/dev/null 2>&1; then
    exit 1
fi

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    if ! hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.title == "qs-master")' >/dev/null 2>&1; then
        exit 1
    fi
fi

exit 0
