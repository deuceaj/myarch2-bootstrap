#!/usr/bin/env bash
# install.sh — turn a fresh archinstall (Cosmic profile) into Primus.
#
# Run as your user from a terminal in the COSMIC session, with Epsilon mounted:
#   sudo mkdir -p /media/Epsilon && sudo mount UUID=91e23279-79fe-4500-a491-1878037460cf /media/Epsilon
#   /media/Epsilon/deuce/myarch2/rebuild/install.sh
#
# Re-run a single step:   ./install.sh greeter      (names: see STEPS below)
# Every step is safe to re-run. Failures are collected and listed at the end.
# It never restarts greetd: the new login screen appears after the reboot.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

LOG="$LOG_DIR/install-$(date +%F-%H%M).log"
exec > >(tee -a "$LOG") 2>&1

STEPS=(preflight pacman_setup install_pacman install_aur system_files boot_config
       drives greeter home_restore umbriel_compat services firewall defaults)

KERNEL_PARAMS=(amdgpu.ppfeaturemask=0xffffffff zswap.enabled=0)
SYSTEM_SERVICES=(NetworkManager bluetooth systemd-resolved lactd mullvad-daemon
                 mullvad-tailscale-bypass tailscaled ufw input-remapper cronie
                 grub-btrfsd fstrim.timer)
USER_SERVICES=(fix-file-dates.path bield-agent.service openrazer-daemon.service
               bible-dashboard.timer)
MOUNTS=(/media/Epsilon /media/Steam /media/Nexus /media/Theatrum /media/Retroludus)
SYS="$PRIVATE_DIR/system"

# ─────────────────────────────────────────────────────────────────────────────
preflight() {
  section "Preflight"
  [[ $EUID -ne 0 ]] || { err "Run as your user (not sudo)."; exit 1; }
  [[ $USER == deuce ]] || warn "User is '$USER', configs expect 'deuce' (paths like /home/deuce)."
  [[ -d "$PRIVATE_DIR/home" ]] || { err "Private backup not found at $PRIVATE_DIR — mount Epsilon first."; exit 1; }
  curl -sfI https://archlinux.org >/dev/null || { err "No internet."; exit 1; }
  $IS_VM && warn "Running in a VM: hardware steps (fans, disks, Windows entry) will be skipped."
  info "Private snapshot from: $(cat "$PRIVATE_DIR/info/snapshot-date.txt" 2>/dev/null || echo unknown)"
  info "Log: $LOG"
  sudo_keepalive
}

pacman_setup() {
  section "pacman.conf: multilib, colour, parallel downloads"
  if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf && log "multilib enabled"
  fi
  sudo sed -i 's/^#Color/Color/; s/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
  sudo pacman -Syu --noconfirm || fail "pacman -Syu"
}

install_pacman() {
  section "Official packages"
  mapfile -t pkgs < <(read_list "$REBUILD_DIR/pkgs/pacman.txt" | tr ' ' '\n' | grep .)
  info "${#pkgs[@]} packages"
  if ! sudo pacman -S --needed --noconfirm "${pkgs[@]}"; then
    warn "Batch install failed — retrying one by one to find the culprit(s)"
    for p in "${pkgs[@]}"; do sudo pacman -S --needed --noconfirm "$p" >/dev/null || fail "pacman: $p"; done
  fi
}

install_aur() {
  section "AUR packages"
  mkdir -p ~/.gnupg && chmod 700 ~/.gnupg
  grep -q auto-key-retrieve ~/.gnupg/gpg.conf 2>/dev/null || echo 'keyserver-options auto-key-retrieve' >> ~/.gnupg/gpg.conf
  if ! command -v yay >/dev/null; then
    info "Building yay-bin"
    local t; t=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$t/yay-bin" \
      && (cd "$t/yay-bin" && makepkg -si --noconfirm) || { fail "yay bootstrap"; return; }
  fi
  mapfile -t pkgs < <(read_list "$REBUILD_DIR/pkgs/aur.txt" | tr ' ' '\n' | grep .)
  local n=0
  for p in "${pkgs[@]}"; do
    n=$((n+1)); info "[$n/${#pkgs[@]}] $p"
    if pacman -Qq "$p" >/dev/null 2>&1; then log "$p already installed"; continue; fi
    yay -S --needed --noconfirm --answerdiff None --answerclean None --answeredit None \
        --removemake "$p" || fail "aur: $p"
  done
}

system_files() {
  section "System files from private backup"
  install_root_file "$SYS/etc/lact/config.yaml"                          /etc/lact/config.yaml
  install_root_file "$SYS/etc/udev/rules.d/99-disable-onboard-bluetooth.rules" /etc/udev/rules.d/99-disable-onboard-bluetooth.rules
  install_root_file "$SYS/etc/udev/rules.d/99-sonix-keypad-kick.rules"   /etc/udev/rules.d/99-sonix-keypad-kick.rules
  install_root_file "$SYS/etc/systemd/system/mullvad-tailscale-bypass.service" /etc/systemd/system/mullvad-tailscale-bypass.service
  install_root_file "$SYS/etc/systemd/system/sonix-keypad-kick.service"  /etc/systemd/system/sonix-keypad-kick.service
  install_root_file "$SYS/etc/systemd/system/grub-btrfsd.service.d/override.conf" /etc/systemd/system/grub-btrfsd.service.d/override.conf
  install_root_file "$SYS/etc/mullvad-tailscale.nft"                     /etc/mullvad-tailscale.nft
  install_root_file "$SYS/usr/local/bin/sonix-keypad-kick"               /usr/local/bin/sonix-keypad-kick 0755
  # Scoped polkit rule: no password prompts for greeter sync, disk mounting,
  # NetworkManager, LACT, input-remapper, Timeshift (pkexec <cmd> still asks)
  install_root_file "$REBUILD_DIR/files/polkit/49-deuce-nopasswd.rules" /etc/polkit-1/rules.d/49-deuce-nopasswd.rules 0644
  # greetd PAM file = stock + gnome-keyring lines (unlocks the keyring at login)
  install_root_file "$SYS/etc/pam.d/greetd"                              /etc/pam.d/greetd
  # Mullvad preferences (auto-connect, LAN sharing — needed for Tailscale —,
  # relay choice). Only settings.json: you sign in fresh, so no device keys
  # are cloned. The daemon must be stopped or it overwrites the file.
  if [[ -f "$SYS/etc/mullvad-vpn/settings.json" ]]; then
    sudo systemctl stop mullvad-daemon 2>/dev/null || true
    install_root_file "$SYS/etc/mullvad-vpn/settings.json" /etc/mullvad-vpn/settings.json 0644
  fi
  sudo udevadm control --reload || true
  sudo systemctl daemon-reload
}

boot_config() {
  section "Kernel parameters, Windows entry"
  # Apply to EVERY boot method present. (Lesson from Primus, Nov 2026: the
  # params lived only in the UKI cmdline, GRUB's plain entry became the default
  # after a grub-mkconfig, and LACT silently lost fan control.)
  local found=false
  if [[ -f /etc/kernel/cmdline ]]; then           # UKI
    found=true; local changed=false
    for k in "${KERNEL_PARAMS[@]}"; do
      grep -qw -- "$k" /etc/kernel/cmdline || { sudo sed -i "s|\$| $k|" /etc/kernel/cmdline; changed=true; }
    done
    $changed && { sudo mkinitcpio -P || fail "mkinitcpio"; }
  fi
  if [[ -f /etc/default/grub ]]; then             # GRUB (normal archinstall)
    found=true
    for k in "${KERNEL_PARAMS[@]}"; do
      grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -qw -- "$k" \
        || sudo sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 $k\"|" /etc/default/grub
    done
  fi
  if sudo test -d /boot/loader/entries; then      # systemd-boot
    found=true
    for f in $(sudo find /boot/loader/entries -name '*.conf'); do
      for k in "${KERNEL_PARAMS[@]}"; do
        sudo grep -qw -- "$k" "$f" || sudo sed -i -E "s|^(options .*)$|\1 $k|" "$f"
      done
    done
    warn "systemd-boot: no snapshot menu or os-prober — GRUB is recommended"
  fi
  $found || fail "boot: no GRUB, UKI cmdline or systemd-boot found — add ${KERNEL_PARAMS[*]} by hand"
  if [[ -f /etc/default/grub ]]; then
    # Custom Windows entry (made 2026-11-16, "Windows Hackintosh (Crucial 240GB
    # SATA)"): restore it and turn os-prober OFF so Windows isn't listed twice.
    # Without it, fall back to os-prober.
    local prober=false
    if [[ -f "$SYS/etc/grub.d/35_windows_hackintosh" ]]; then
      install_root_file "$SYS/etc/grub.d/35_windows_hackintosh" /etc/grub.d/35_windows_hackintosh 0755
      prober=true
    fi
    if grep -q '^#\?GRUB_DISABLE_OS_PROBER' /etc/default/grub; then
      sudo sed -i "s/^#\\?GRUB_DISABLE_OS_PROBER.*/GRUB_DISABLE_OS_PROBER=$prober/" /etc/default/grub
    else
      echo "GRUB_DISABLE_OS_PROBER=$prober" | sudo tee -a /etc/default/grub >/dev/null
    fi
    sudo grub-mkconfig -o /boot/grub/grub.cfg || fail "grub-mkconfig"
    $IS_VM || sudo grep -q -i windows /boot/grub/grub.cfg || fail "GRUB: no Windows entry found (is sda connected? Part 2 done?)"
  fi
}

drives() {
  section "Drives (fstab)"
  sudo mkdir -p "${MOUNTS[@]}"
  if $IS_VM; then
    # Test VM: mount Primus's read-only Epsilon share at every boot instead.
    grep -q '^epsilon ' /etc/fstab || echo 'epsilon /media/Epsilon/deuce 9p trans=virtio,version=9p2000.L,ro,nofail 0 0' \
      | sudo tee -a /etc/fstab >/dev/null && log "VM: Epsilon share added to fstab"
    warn "real disks skipped (VM)"; return
  fi
  [[ -f "$SYS/etc/fstab" ]] || { fail "no saved fstab"; return; }
  [[ -e /etc/fstab.bak-rebuild ]] || sudo cp -a /etc/fstab /etc/fstab.bak-rebuild
  local m line
  for m in "${MOUNTS[@]}"; do
    awk -v m="$m" '$1 !~ /^#/ && $2 == m' /etc/fstab | grep -q . && { log "$m already in fstab"; continue; }
    line=$(awk -v m="$m" '$1 !~ /^#/ && $2 == m' "$SYS/etc/fstab")
    [[ -n $line ]] || { fail "fstab: no saved entry for $m"; continue; }
    echo "$line" | sudo tee -a /etc/fstab >/dev/null && log "fstab += $m"
  done
  # local disks must exist (UUIDs survive a reinstall as long as they're not formatted)
  for u in 91e23279-79fe-4500-a491-1878037460cf 86c67d03-9bca-4a0f-8e81-0577808b13ec; do
    [[ -e /dev/disk/by-uuid/$u ]] || fail "disk UUID=$u not found (Epsilon/Steam)"
  done
  sudo systemctl daemon-reload
  sudo mount -a || fail "mount -a reported errors"
}

greeter() {
  section "Login screen: greetd + noctalia-greeter"
  local dm
  for dm in cosmic-greeter gdm sddm lightdm ly; do
    systemctl is-enabled "$dm.service" >/dev/null 2>&1 && { sudo systemctl disable "$dm.service" && log "disabled $dm"; }
  done
  getent passwd greeter >/dev/null || fail "greeter user missing (greetd not installed?)"
  [[ -f /etc/greetd/config.toml && ! -e /etc/greetd/config.toml.bak-rebuild ]] && sudo cp -a /etc/greetd/config.toml /etc/greetd/config.toml.bak-rebuild
  sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
command = "/usr/bin/noctalia-greeter-session -- --session Umbriel --user deuce"
user = "greeter"
EOF
  sudo install -d -m 0750 -o greeter -g greeter /var/lib/noctalia-greeter
  sudo noctalia-greeter-apply-appearance --setup-system || fail "noctalia-greeter --setup-system"
  if [[ -f "$SYS/var/lib/noctalia-greeter/greeter.toml" ]]; then
    sudo install -m 0644 -o greeter -g greeter "$SYS/var/lib/noctalia-greeter/greeter.toml" /var/lib/noctalia-greeter/greeter.toml
    log "restored greeter.toml (your layout)"
  fi
  sudo noctalia-greeter passwordless-sync enable "$USER" >/dev/null 2>&1 || true
  # Enable only — NEVER restart greetd from a running session (locks you out).
  sudo systemctl enable greetd.service && log "greetd enabled (takes over after reboot)"
}

home_restore() {
  section "Home settings from private backup"
  rsync -a "$PRIVATE_DIR/home/" "$HOME/" && log "configs restored"
  chmod 700 ~/.ssh 2>/dev/null; chmod 600 ~/.ssh/id_* ~/.local/.smbcredentials* 2>/dev/null
  # Home folders that live on Epsilon
  local name target
  while IFS=$'\t' read -r name target; do
    [[ -L "$HOME/$name" ]] && { [[ "$(readlink "$HOME/$name")" == "$target" ]] && continue; rm "$HOME/$name"; }
    if [[ -d "$HOME/$name" ]]; then
      rmdir "$HOME/$name" 2>/dev/null || { mv "$HOME/$name" "$HOME/$name.orig"; warn "$name had files — moved to $name.orig"; }
    fi
    ln -s "$target" "$HOME/$name" && log "~/$name -> $target"
    [[ -e "$target" ]] || warn "~/$name points to $target, which isn't there yet"
  done < "$PRIVATE_DIR/info/home-symlinks.tsv"
  # xdg-user-dirs points a folder at $HOME/ if it didn't exist yet (the Epsilon
  # links come later), which sent screenshots/downloads into ~ (2026-11-21).
  for kv in DOWNLOAD:Downloads DOCUMENTS:Documents MUSIC:Music PICTURES:Pictures VIDEOS:Videos; do
    xdg-user-dirs-update --set "${kv%%:*}" "$HOME/${kv#*:}"
  done
  mkdir -p "$HOME/Pictures/Screenshots" 2>/dev/null || true
  # Cursor: Bibata everywhere (GTK, X11 apps, COSMIC)
  mkdir -p ~/.icons/default ~/.config/environment.d
  printf '[Icon Theme]\nInherits=Bibata-Modern-Classic\n' > ~/.icons/default/index.theme
  printf 'XCURSOR_THEME=Bibata-Modern-Classic\nXCURSOR_SIZE=24\n' > ~/.config/environment.d/cursor.conf
  sed -i 's/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Bibata-Modern-Classic/' ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini 2>/dev/null || true
}

umbriel_compat() {
  section "umbriel config vs the installed umbriel-git version"
  # umbriel-git builds the newest commit, which can change config formats
  # (seen in the VM test 2026-11-13: follows_mouse bool -> "off"/"sloppy"/"always").
  local cfg=~/.config/umbriel/cfg/general.toml out
  out=$(umbriel config validate 2>&1) && { log "config valid ($(pacman -Q umbriel-git | cut -d' ' -f2))"; return; }
  if grep -q 'follows_mouse' <<<"$out"; then
    sed -i -E 's/^(follows_mouse *= *)true\b/\1"sloppy"/; s/^(follows_mouse *= *)false\b/\1"off"/' "$cfg"
    log 'migrated follows_mouse true -> "sloppy"'
  fi
  out=$(umbriel config validate 2>&1) && log "config valid after migration" \
    || fail "umbriel config invalid: $(grep -m3 -E 'warning|error' <<<"$out" | tr '\n' ' ')"
}

services() {
  section "Services"
  local s
  for s in "${SYSTEM_SERVICES[@]}"; do
    systemctl list-unit-files "$s"* --no-legend 2>/dev/null | grep -q . || { fail "service not found: $s"; continue; }
    sudo systemctl enable "$s" >/dev/null 2>&1 && log "enabled $s" || fail "enable $s"
  done
  # systemd-resolved needs the stub resolv.conf (Mullvad + Tailscale DNS)
  [[ "$(readlink /etc/resolv.conf)" == */stub-resolv.conf ]] || sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  systemctl --user daemon-reload
  for s in "${USER_SERVICES[@]}"; do
    systemctl --user enable "$s" >/dev/null 2>&1 && log "enabled (user) $s" || fail "enable (user) $s"
  done
  sudo usermod -aG gamemode,openrazer "$USER" && log "groups: gamemode, openrazer (active after reboot)"
}

firewall() {
  section "Firewall (ufw)"
  if [[ -f "$SYS/etc/ufw/user.rules" ]]; then
    install_root_file "$SYS/etc/ufw/user.rules"  /etc/ufw/user.rules  0640
    install_root_file "$SYS/etc/ufw/user6.rules" /etc/ufw/user6.rules 0640
  fi
  sudo ufw default deny incoming >/dev/null
  sudo ufw allow 53317/tcp comment LocalSend >/dev/null
  sudo ufw allow 53317/udp comment LocalSend >/dev/null
  sudo ufw --force enable >/dev/null && log "ufw on"
}

defaults() {
  section "Default apps (so COSMIC's apps don't take over)"
  xdg-mime default thunar.desktop inode/directory
  xdg-mime default brave-browser.desktop x-scheme-handler/http x-scheme-handler/https text/html
  mkdir -p ~/.local/state/rebuild
  cp ~/.config/mimeapps.list ~/.local/state/rebuild/mimeapps.list.expected
  log "mimeapps.list pinned (doctor.sh warns if COSMIC changes it)"
  if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
if (($# > 0)); then
  preflight; for s in "$@"; do "$s"; done; print_summary; exit
fi
for s in "${STEPS[@]}"; do "$s"; done
print_summary
section "Next"
echo "  1. Reboot (the noctalia login screen appears; pick Umbriel)."
echo "  2. In umbriel run:  $REBUILD_DIR/first-login.sh"
echo "  Log: $LOG"
read -rp "Reboot now? [y/N] " a; [[ ${a,,} == y ]] && systemctl reboot
