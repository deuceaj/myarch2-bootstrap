#!/usr/bin/env python3
"""Turn on the noctalia CSS snippet in the Obsidian vaults listed below.
Run as the post_hook of the obsidian templates in templates.toml."""
import json, os

VAULTS = [
    "/media/Nexus/obsidian/Bible Study 2025",
    "/media/Nexus/obsidian/Personal",
]

for vault in VAULTS:
    path = os.path.join(vault, ".obsidian", "appearance.json")
    if not os.path.isdir(os.path.dirname(path)):
        continue
    data = {}
    if os.path.isfile(path):
        with open(path) as f:
            data = json.load(f)
    snippets = data.setdefault("enabledCssSnippets", [])
    if "noctalia" not in snippets:
        snippets.append("noctalia")
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
