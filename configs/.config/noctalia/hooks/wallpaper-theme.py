#!/usr/bin/env python3
"""Hybrid wallpaper theming, run by noctalia's wallpaper_changed and started hooks.

1. Shell accent: the bar/menus keep the MacDark graphite + white palette, but
   its accent (primary) becomes the wallpaper's most prominent vivid color.
2. Apps: Neovim, Spotify (Spicetify Comfy), Obsidian, cava, Thunar and
   VSCode get a full
   palette generated from the wallpaper (`noctalia theme <image> --render`).
   These apps are deliberately NOT in noctalia's own template lists, so the
   two never write the same files.
3. Bottom audio visualizer: the wallpaper's two most prominent vivid colors.
"""
import colorsys
import fcntl
import json
import os
import re
import shutil
import subprocess

HOME = os.path.expanduser("~")
NOCTALIA = f"{HOME}/.config/noctalia"
TEMPLATES = f"{NOCTALIA}/templates"
PALETTE = f"{NOCTALIA}/palettes/MacDark.json"
SCHEME = "vibrant"  # wallpaper palette generator for the apps
VISUALIZER = "desktop_widgets.widget.audio_bars.settings"

OBSIDIAN_VAULTS = [
    "/media/Nexus/obsidian/Bible Study 2025",
    "/media/Nexus/obsidian/Personal",
]

# (template, output) pairs rendered from the wallpaper palette.
APP_TEMPLATES = [
    ("neovim-matugen.lua", f"{HOME}/.config/nvim/lua/matugen.lua"),
    ("spicetify-comfy.ini", f"{HOME}/.config/spicetify/Themes/Comfy/color.ini"),
    ("cava.ini", f"{HOME}/.config/cava/themes/noctalia"),
    # Thunar only (scoped to window.thunar); imported at the top of gtk-3.0/gtk.css.
    ("thunar.css", f"{HOME}/.config/gtk-3.0/noctalia-thunar.css"),
    # VSCode: overwrites the NoctaliaTheme extension's color theme file.
    ("vscode.json", f"{HOME}/.vscode/extensions/noctalia.noctaliatheme-0.0.5/themes/NoctaliaTheme-color-theme.json"),
] + [("obsidian.css", f"{v}/.obsidian/snippets/noctalia.css") for v in OBSIDIAN_VAULTS]


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def wallpaper():
    path = os.environ.get("NOCTALIA_WALLPAPER_PATH", "")
    if path and os.path.isfile(path):
        return path
    out = run("noctalia", "msg", "wallpaper-get", "DP-1").stdout.strip()
    return out if os.path.isfile(out) else ""


# ── Dominant colors ──────────────────────────────────────────────────────────

def prominent_colors(path, want=2):
    """Most prominent vivid colors: pixel share weighted by saturation and
    brightness (so dark/grey areas don't win), with clearly different hues."""
    out = run("magick", path, "-resize", "200x200", "-colors", "12",
              "-format", "%c", "histogram:info:-").stdout
    colors = []
    for count, hexval in re.findall(r"^\s*(\d+):.*?(#[0-9A-Fa-f]{6})", out, re.M):
        r, g, b = (int(hexval[i:i + 2], 16) / 255 for i in (1, 3, 5))
        colors.append((int(count), *colorsys.rgb_to_hsv(r, g, b)))
    total = sum(c[0] for c in colors) or 1
    scored = sorted(((n / total) * (0.3 + s) * v, h, s, v)
                    for n, h, s, v in colors if v >= 0.25)
    chosen = []
    for _, h, s, v in reversed(scored):
        if all(min(abs(h - ch), 1 - abs(h - ch)) > 0.07 for ch, _, _ in chosen):
            chosen.append((h, s, v))
        if len(chosen) == want:
            break
    return chosen


def to_hex(h, s, v):
    # Lift dim/muted picks so they read clearly on dark surfaces.
    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, max(s, 0.45) * 1.1), max(v, 0.85))
    return "#{:02x}{:02x}{:02x}".format(round(r * 255), round(g * 255), round(b * 255))


def text_on(hexval):
    r, g, b = (int(hexval[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return "#1c1c1e" if 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.55 else "#ffffff"


# ── 1. Shell accent ──────────────────────────────────────────────────────────

def set_shell_accent(accent):
    with open(PALETTE) as f:
        palette = json.load(f)
    for variant in ("dark", "light"):
        if variant in palette:
            palette[variant]["mPrimary"] = accent
            palette[variant]["mOnPrimary"] = text_on(accent)
    with open(PALETTE, "w") as f:
        json.dump(palette, f, indent=2)
    run("noctalia", "msg", "color-scheme-set", "custom", "MacDark")


# ── 2. App themes ────────────────────────────────────────────────────────────

def render_apps(path):
    mode = run("noctalia", "msg", "theme-mode-get").stdout.strip() or "dark"
    before = {out: _read(out) for _, out in APP_TEMPLATES}
    args = ["noctalia", "theme", path, f"--{mode}", "--scheme", SCHEME]
    for template, out in APP_TEMPLATES:
        if os.path.isdir(os.path.dirname(os.path.dirname(out))):
            os.makedirs(os.path.dirname(out), exist_ok=True)
            args += ["-r", f"{TEMPLATES}/{template}:{out}"]
    run(*args)
    return {out for _, out in APP_TEMPLATES if _read(out) != before[out]}


def _read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def reload_apps(changed):
    # Neovim: the generated module reloads itself on SIGUSR1.
    run("pkill", "-USR1", "-x", "nvim")
    # cava: make sure it uses the noctalia theme, then live-reload.
    run("bash", "/usr/share/noctalia/assets/templates/cava/apply.sh")
    # Obsidian: switch the snippet on in each vault (hot-reloads from disk).
    run(f"{NOCTALIA}/hooks/obsidian-enable.py")
    # Spotify: one spicetify apply at a time; concurrent applies corrupt it.
    comfy = f"{HOME}/.config/spicetify/Themes/Comfy/color.ini"
    if comfy in changed and shutil.which("spicetify"):
        lock_path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "spicetify-apply.lock")
        with open(lock_path, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            run("spicetify", "-q", "apply", "--no-restart")


# ── 3. Visualizer ────────────────────────────────────────────────────────────

def set_visualizer(c1, c2):
    for key, val in (("color_1", c1), ("color_2", c2)):
        run("noctalia", "msg", "config-set", f"{VISUALIZER}.{key}", f'"{val}"')


def main():
    path = wallpaper()
    if not path:
        return
    picks = prominent_colors(path)
    if picks:
        accent = to_hex(*picks[0])
        set_shell_accent(accent)
        second = to_hex(*picks[1]) if len(picks) > 1 else accent
        set_visualizer(accent, second)
    changed = render_apps(path)
    reload_apps(changed)
    print(f"{os.path.basename(path)}: accent {accent if picks else '-'}, "
          f"apps updated: {len(changed)}")


if __name__ == "__main__":
    main()
