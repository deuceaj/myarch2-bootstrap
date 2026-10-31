#!/usr/bin/env python3
"""Open a saved Remmina profile fullscreen on the umbriel workspace that is focused right now.

Usage: remmina-here.py <profile-file-name-or-path>

Remmina tries to fullscreen itself (viewmode=4) and may pick a different
monitor, so after the connection window appears we pull it back to the
workspace that was focused at keypress time and make sure it is fullscreen.

Ported from ~/.config/niri/scripts/remmina-here.py (niri msg → umbriel).
"""
import json
import os
import subprocess
import sys
import time

PROFILE_DIR = os.path.expanduser("~/.local/share/remmina")
MAIN_TITLE = "Remmina Remote Desktop Client"


def umbriel_json(*args):
    out = subprocess.run(["umbriel", *args, "--json"], capture_output=True, text=True).stdout
    return json.loads(out) if out.strip() else None


def action(*args):
    subprocess.run(["umbriel", "msg", *args])


def remmina_windows():
    return {w["id"]: w for w in umbriel_json("windows") or [] if "remmina" in (w.get("app_id") or "").lower()}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    profile = sys.argv[1]
    if not os.path.isabs(profile):
        profile = os.path.join(PROFILE_DIR, profile)

    ws = next(w for w in umbriel_json("workspaces") if w["focused"])
    before = set(remmina_windows())

    subprocess.Popen(["remmina", "-c", profile],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    # Wait up to 60s (SSH tunnel / auth prompts can take a while) for the connection window.
    deadline = time.time() + 60
    while time.time() < deadline:
        time.sleep(0.3)
        new = [w for i, w in remmina_windows().items() if i not in before and w.get("title") != MAIN_TITLE]
        if new:
            break
    else:
        return

    win = new[0]
    time.sleep(0.5)  # let Remmina finish its own fullscreen dance first
    win = remmina_windows().get(win["id"], win)
    wid = win["id"]

    # Workspace actions act on the focused window, so focus it first.
    action("window-focus", wid)
    if win.get("workspace") != ws["id"]:
        action("window-move-to-workspace", ws["name"], "--output", ws["output"])
        action("window-focus", wid)

    win = remmina_windows().get(wid, win)
    if not win.get("fullscreen"):
        action("window-toggle-fullscreen")


if __name__ == "__main__":
    main()
