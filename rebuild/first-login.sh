#!/usr/bin/env bash
# first-login.sh — run once inside umbriel after install.sh + reboot.
# Checks monitor names, restores Steam's library/Proton settings, then runs
# doctor.sh and lists what still needs you (sign-ins). Safe to re-run.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
LOG="$LOG_DIR/first-login-$(date +%F-%H%M).log"
exec > >(tee -a "$LOG") 2>&1

section "Session"
if ! umbriel outputs --json >/dev/null 2>&1; then
  err "Not running inside umbriel. Log in with the Umbriel session and run this again."; exit 1
fi
log "umbriel is running"

section "Monitor names"
mapfile -t want < <(grep -oE '^\[output\.[^].]+\]' ~/.config/umbriel/cfg/outputs.toml | sed -E 's/^\[output\.(.*)\]$/\1/; s/"//g')
have=$(umbriel outputs --json | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("outputs",[]); print("\n".join(o.get("name","") for o in d))')
for w in "${want[@]}"; do
  if grep -qx "$w" <<<"$have"; then log "$w found"
  else fail "config expects output $w but umbriel sees: $(tr '\n' ' ' <<<"$have")— rename it in ~/.config/umbriel/cfg/outputs.toml, noctalia desktop.toml + settings"; fi
done
$IS_VM && warn "VM: monitor names will differ from Primus (expected here)"

section "Steam"
STEAM=~/.local/share/Steam
if [[ ! -f $STEAM/config/config.vdf ]]; then
  warn "Steam hasn't been set up yet. Start Steam, sign in, then quit it fully (Steam menu → Exit) and re-run this."
elif ! mountpoint -q /media/Steam && ! $IS_VM; then
  fail "/media/Steam not mounted — the game library lives there"
else
  if pgrep -x steam >/dev/null; then info "Shutting Steam down"; steam -shutdown >/dev/null 2>&1; sleep 8; fi
  pgrep -x steam >/dev/null && { fail "Steam still running — quit it and re-run"; }
  if ! pgrep -x steam >/dev/null; then
    cp -a $STEAM/config/config.vdf $STEAM/config/config.vdf.bak-first-login 2>/dev/null
    rsync -a "$PRIVATE_DIR/steam/" "$STEAM/" && log "restored library folders, launch options, GE-Proton default"
  fi
fi

section "Health check"
"$REBUILD_DIR/doctor.sh" || true

section "Still needs you"
cat <<'EOF'
  [ ] noctalia Settings → Security → Noctalia Greeter → Sync Now (+ Auto-Sync)
  [ ] Mullvad: sign in (mullvad account login)       [ ] Tailscale: sudo tailscale up
  [ ] Firefox / Floorp / Chromium: check the profile came back signed in
  [ ] Spotify, NordPass, pCloud, Notion, Discord, Zoom, Claude: sign in
  [ ] Steam: sign in (then re-run this script once)
  [ ] spicetify: spicetify backup apply (after Spotify has run once)
  [ ] Change your login password if not done yet: passwd
EOF
print_summary
echo "Log: $LOG"
