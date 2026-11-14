#!/usr/bin/env bash
# backup-private.sh — snapshot Primus's personal settings, secrets, system files
# and Steam config into the PRIVATE folder on Epsilon (default
# /media/Epsilon/deuce/private, mode 700). Nothing here is ever committed.
# Run it on the working system before a reinstall (and any time after changes).
#
#   ./backup-private.sh          # full snapshot (asks for sudo once for /etc bits)
#
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ $EUID -ne 0 ]] || { err "Run as your user, not root."; exit 1; }
mountpoint -q "$EPSILON" || { err "$EPSILON is not mounted."; exit 1; }

mkdir -p "$PRIVATE_DIR"/{home,system,steam,info}
chmod 700 "$PRIVATE_DIR"

# Caches and junk that rebuild themselves (and clutter a backup).
EXCLUDES=(
  --exclude='Cache/' --exclude='cache/' --exclude='cache2/' --exclude='Code Cache/'
  --exclude='GPUCache/' --exclude='ShaderCache/' --exclude='GrShaderCache/'
  --exclude='DawnCache/' --exclude='DawnGraphiteCache/' --exclude='DawnWebGPUCache/'
  --exclude='CacheStorage/' --exclude='Crashpad/' --exclude='crashes/'
  --exclude='*.bak-*' --exclude='*.backup-*'
  --exclude='/.local/state/noctalia/clipboard/'
  --exclude='/.claude/projects/*/*.jsonl' --exclude='/.claude/shell-snapshots/'
  --exclude='/.claude/file-history/' --exclude='/.claude/todos/' --exclude='/.claude/cache/'
  # DMS leftovers that should not come back
  --exclude='/.config/systemd/user/default.target.wants/dsearch.service'
  --exclude='/.config/systemd/user/niri.service.d/'
)

section "Home settings → $PRIVATE_DIR/home"
list=$(mktemp)
while IFS= read -r p; do
  [[ -e "$HOME/$p" ]] && echo "$p" >> "$list" || warn "not present, skipped: $p"
done < <(read_list "$REBUILD_DIR/home-manifest.txt")
rsync -a -r --relative --delete --delete-excluded "${EXCLUDES[@]}" \
      --files-from="$list" "$HOME/" "$PRIVATE_DIR/home/"
rm -f "$list"
log "home: $(du -sh "$PRIVATE_DIR/home" | cut -f1)"

# Home folders that are links into Epsilon (Downloads, Pictures, ...)
find "$HOME" -maxdepth 1 -type l -lname '/media/*' -printf '%f\t%l\n' > "$PRIVATE_DIR/info/home-symlinks.tsv"
log "home links: $(wc -l < "$PRIVATE_DIR/info/home-symlinks.tsv")"

section "Steam config → $PRIVATE_DIR/steam"
STEAM="$HOME/.local/share/Steam"
if [[ -d "$STEAM" ]]; then
  ( cd "$STEAM" && rsync -a -r --relative --delete \
      config/config.vdf config/loginusers.vdf steamapps/libraryfolders.vdf \
      userdata/*/config/localconfig.vdf compatibilitytools.d/ \
      "$PRIVATE_DIR/steam/" ) && log "steam: $(du -sh "$PRIVATE_DIR/steam" | cut -f1)"
else
  warn "no Steam folder, skipped"
fi

section "System files → $PRIVATE_DIR/system (sudo)"
SYSTEM_FILES=(
  /etc/fstab /etc/default/grub /etc/kernel/cmdline
  /etc/lact/config.yaml
  /etc/udev/rules.d/99-disable-onboard-bluetooth.rules
  /etc/udev/rules.d/99-sonix-keypad-kick.rules
  /etc/systemd/system/mullvad-tailscale-bypass.service
  /etc/systemd/system/sonix-keypad-kick.service
  /etc/systemd/system/grub-btrfsd.service.d/override.conf
  /etc/mullvad-tailscale.nft
  /usr/local/bin/sonix-keypad-kick
  /etc/pam.d/greetd
  /etc/greetd/config.toml
  /etc/ufw/user.rules /etc/ufw/user6.rules
  /etc/mullvad-vpn/settings.json    # auto-connect, LAN sharing, relay prefs (NOT account/device keys)
  /var/lib/noctalia-greeter/
)
sudo rsync -a -r --relative --delete "${SYSTEM_FILES[@]}" "$PRIVATE_DIR/system/" 2>&1 | grep -v 'No such file' || true
sudo chown -R "$USER:$USER" "$PRIVATE_DIR/system"
log "system: $(find "$PRIVATE_DIR/system" -type f | wc -l) files"

section "Package snapshot → $PRIVATE_DIR/info"
pacman -Qqen > "$PRIVATE_DIR/info/pkgs-native.txt"
pacman -Qqem > "$PRIVATE_DIR/info/pkgs-aur.txt"
systemctl list-unit-files --state=enabled --no-legend | awk '{print $1}' > "$PRIVATE_DIR/info/services-system.txt"
systemctl --user list-unit-files --state=enabled --no-legend | awk '{print $1}' > "$PRIVATE_DIR/info/services-user.txt"
date -Iseconds > "$PRIVATE_DIR/info/snapshot-date.txt"

"$REBUILD_DIR/backup-claude-chats.sh" || warn "Claude chats backup reported problems"

chmod -R go-rwx "$PRIVATE_DIR"
section "Done"
log "Private snapshot: $(du -sh "$PRIVATE_DIR" | cut -f1) at $PRIVATE_DIR (mode 700)"
