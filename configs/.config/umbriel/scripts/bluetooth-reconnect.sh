#!/bin/bash
# Reconnect known Bluetooth audio devices at startup.
# BlueZ only auto-reconnects on link loss while already connected — it
# does nothing for a device that's simply not connected yet at boot.

DEVICES=(
    "AF:ED:75:D0:E5:98"  # Hayo Speakers
)

wait_for_adapter() {
    for _ in $(seq 1 20); do
        bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && return 0
        sleep 1
    done
    return 1
}

wait_for_adapter || exit 0

for mac in "${DEVICES[@]}"; do
    for _ in $(seq 1 5); do
        bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes" && break
        bluetoothctl connect "$mac" &>/dev/null
        sleep 3
    done
done
