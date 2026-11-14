#!/usr/bin/env bash
# doctor.sh — check that Primus is set up the way it should be. Read-only.
# Prints ✓ / ✗ / – (skipped) per item; exit code = number of ✗.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

bad=0
ok()   { echo "  ${G}✓${N} $*"; }
no()   { echo "  ${R}✗${N} $*"; bad=$((bad+1)); }
skip() { echo "  ${Y}–${N} $*"; }
check(){ local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
hw()   { if $IS_VM; then skip "$1 (VM)"; else check "$@"; fi; }

section "Packages"
mapfile -t want < <( { read_list "$REBUILD_DIR/pkgs/pacman.txt"; read_list "$REBUILD_DIR/pkgs/aur.txt"; } | tr ' ' '\n' | grep .)
missing=$(for p in "${want[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || pacman -Qqg "$p" >/dev/null 2>&1 || echo "$p"; done)
[[ -z $missing ]] && ok "all ${#want[@]} listed packages installed" || no "missing: $(echo $missing)"

section "GPU / fans"
hw "kernel param amdgpu.ppfeaturemask" grep -qw amdgpu.ppfeaturemask=0xffffffff /proc/cmdline
check "lactd running" systemctl is-active lactd
check "LACT fan curve config present" test -f /etc/lact/config.yaml
hw "GPU fan control exposed (gpu_od/fan_ctrl)" bash -c 'ls /sys/class/drm/card*/device/gpu_od/fan_ctrl'

section "Login screen"
check "greetd enabled" systemctl is-enabled greetd
check "greetd uses noctalia-greeter" grep -q noctalia-greeter-session /etc/greetd/config.toml
check "no other display manager enabled" bash -c '! systemctl is-enabled cosmic-greeter gdm sddm lightdm 2>/dev/null | grep -qx enabled'
check "greeter state dir 0750 greeter" bash -c '[[ $(stat -c %a:%U /var/lib/noctalia-greeter) == 750:greeter ]]'
check "keyring unlocks at login (pam)" grep -q pam_gnome_keyring /etc/pam.d/greetd

section "Drives"
for m in /media/Epsilon /media/Steam; do hw "$m mounted" mountpoint -q "$m"; done
for m in /media/Nexus /media/Theatrum /media/Retroludus; do hw "$m in fstab (network, on demand)" grep -q " $m " /etc/fstab; done
while IFS=$'\t' read -r name target; do
  check "~/$name → $target" test -L "$HOME/$name" -a -e "$HOME/$name"
done < "$PRIVATE_DIR/info/home-symlinks.tsv"

section "Boot"
check "os-prober enabled in GRUB" grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
if [[ -r /boot/grub/grub.cfg ]] || sudo -n true 2>/dev/null; then
  hw "Windows entry in GRUB menu" sudo -n grep -qi windows /boot/grub/grub.cfg
else skip "Windows entry in GRUB menu (needs sudo: run 'sudo -v' first)"; fi
check "kernel params also in GRUB default entry" bash -c 'grep -E "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -q amdgpu.ppfeaturemask'
check "grub-btrfsd running (snapshots in menu)" systemctl is-active grub-btrfsd

section "System services"
hw "bluetooth active" systemctl is-active bluetooth
for s in NetworkManager systemd-resolved mullvad-daemon tailscaled ufw input-remapper cronie; do
  check "$s active" systemctl is-active "$s"
done
check "mullvad-tailscale-bypass enabled" systemctl is-enabled mullvad-tailscale-bypass
if [[ -r /etc/ufw/user.rules ]] || sudo -n true 2>/dev/null; then
  check "LocalSend port open in ufw" sudo -n grep -q 53317 /etc/ufw/user.rules
else skip "LocalSend port in ufw (needs sudo: run 'sudo -v' first)"; fi

section "Mullvad + Tailscale together"
# The conflict seen before: with Mullvad connected, traffic to tailnet devices
# was dropped. mullvad-tailscale-bypass (nft table) routes it around Mullvad.
# These checks use real app-style traffic (ICMP to a tailnet IP, MagicDNS),
# not `tailscale ping`, which works even when apps are blocked.
if mullvad status 2>/dev/null | grep -q '^Connected' && tailscale status >/dev/null 2>&1; then
  peer=$(tailscale status --json 2>/dev/null | python3 -I -c '
import json,sys
d=json.load(sys.stdin)
for p in (d.get("Peer") or {}).values():
    if p.get("Online") and p.get("TailscaleIPs"):
        print(p["TailscaleIPs"][0], (p.get("DNSName") or "").rstrip(".")); break')
  if [[ -n $peer ]]; then
    read -r pip pname <<<"$peer"
    check "tailnet reachable with Mullvad on (ping $pname)" ping -c1 -W3 "$pip"
    check "MagicDNS names resolve ($pname)" getent hosts "$pname"
  else skip "no online tailnet peer to test against"; fi
  check "Mullvad LAN sharing allowed" bash -c 'mullvad lan get | grep -q allow'
  check "bypass rules loaded" systemctl is-active mullvad-tailscale-bypass
else skip "Mullvad and Tailscale not both connected — nothing to test"; fi

section "User services"
for s in fix-file-dates.path bield-agent.service openrazer-daemon.service bible-dashboard.timer craft-update-check.timer; do
  check "$s enabled" systemctl --user is-enabled "$s"
done
check "in gamemode + openrazer groups" bash -c 'id -nG | grep -qw gamemode && id -nG | grep -qw openrazer'

section "Desktop"
check "umbriel config valid" umbriel config validate
check "LXQt file dialog wired (portal conf)" grep -q 'FileChooser=lxqt' ~/.config/xdg-desktop-portal/umbriel-portals.conf
check "LXQt dialog theme drop-in" test -f ~/.config/systemd/user/xdg-desktop-portal-lxqt.service.d/qt6ct.conf
check "noctalia generated qt6ct colours" test -f ~/.config/qt6ct/colors/noctalia.conf
check "Bibata cursor installed" test -d /usr/share/icons/Bibata-Modern-Classic
if [[ -f ~/.local/state/rebuild/mimeapps.list.expected ]]; then
  check "default apps unchanged (not taken over by COSMIC)" cmp -s ~/.config/mimeapps.list ~/.local/state/rebuild/mimeapps.list.expected
else skip "default apps (install.sh not run yet)"; fi
check "folders open in Thunar" bash -c '[[ $(xdg-mime query default inode/directory) == thunar.desktop ]]'

section "Steam"
check "GE-Proton installed" bash -c 'ls -d ~/.local/share/Steam/compatibilitytools.d/GE-Proton*'
check "GE-Proton is the default tool" grep -q GE-Proton ~/.local/share/Steam/config/config.vdf
hw "library on /media/Steam" grep -q /media/Steam ~/.local/share/Steam/steamapps/libraryfolders.vdf

echo
if ((bad == 0)); then log "All good."; else err "$bad problem(s). Re-run a step with: $REBUILD_DIR/install.sh <step>"; fi
exit $bad
