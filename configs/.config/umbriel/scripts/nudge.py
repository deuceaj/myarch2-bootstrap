#!/usr/bin/env python3
"""Mod+Alt+arrows: move the focused window freely, overriding umbriel's centering.

A tiled window is floated in place first (umbriel keeps a lone window centered
and won't scroll it), then moved. Mod+T re-tiles it, centered again.

Usage: nudge.py left|right|up|down [step]
  step: fraction of the output per press (default 0.05; Mod+Alt+Shift uses 0.01)
"""
import json
import subprocess
import sys

DIRECTIONS = ("left", "right", "up", "down")


def query(*args):
    out = subprocess.run(["umbriel", *args, "--json"], capture_output=True, text=True).stdout
    return json.loads(out) if out.strip() else None


def msg(*args):
    subprocess.run(["umbriel", "msg", *args], capture_output=True)


def main():
    direction = sys.argv[1] if len(sys.argv) > 1 else ""
    if direction not in DIRECTIONS:
        sys.exit(__doc__)
    step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
    win = query("focused-window")
    if not win:
        return

    if not win["floating"]:
        msg("window-toggle-floating", win["id"])

    output = next((o for o in query("outputs") or [] if o.get("name") == win["output"]), {})
    area = output.get("usable_area") or output.get("logical") or {}
    width = area.get("width") or area.get("w") or 1920
    height = area.get("height") or area.get("h") or 1080
    dx, dy = {
        "left": (-round(width * step), 0),
        "right": (round(width * step), 0),
        "up": (0, -round(height * step)),
        "down": (0, round(height * step)),
    }[direction]
    msg("window-move-by", str(dx), str(dy), "--window", win["id"])


if __name__ == "__main__":
    main()
