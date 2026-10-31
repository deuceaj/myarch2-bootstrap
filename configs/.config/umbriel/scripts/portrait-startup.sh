#!/bin/bash
# Open the portrait-monitor apps one at a time so they stack top to bottom in
# this order on workspace 7. Placement and heights come from window rules in
# cfg/rules.toml; this script only controls the order.
# Replaces ~/.config/niri/scripts/right-monitor-startup.sh.

APPS=(
    "spotify|Spotify"
    "kitty --class cava -e cava|cava"
    "corectrl|org.corectrl.CoreCtrl"
)

wait_for_app() {
    for _ in $(seq 1 30); do
        umbriel windows --json 2>/dev/null | python3 -c \
            'import json,sys; sys.exit(not any(w["app_id"] == sys.argv[1] for w in json.load(sys.stdin)))' "$1" \
            && return 0
        sleep 1
    done
    return 1
}

for entry in "${APPS[@]}"; do
    cmd=${entry%%|*}
    app_id=${entry##*|}
    command -v "${cmd%% *}" >/dev/null || continue
    setsid -f $cmd >/dev/null 2>&1
    wait_for_app "$app_id"
done
