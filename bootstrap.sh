#!/usr/bin/env bash
#
# bootstrap.sh — first thing to run on a fresh Arch install (Cosmic profile).
#
#   sudo pacman -S --needed git
#   git clone https://github.com/deuceaj/myarch2-bootstrap.git ~/myarch2
#   ~/myarch2/bootstrap.sh
#
# Finds the Epsilon drive (Samsung 980, btrfs, label "Epsilon"), adds it to
# /etc/fstab, mounts it at /media/Epsilon, checks the private backup is there,
# then offers to run rebuild/install.sh. It never formats or partitions anything.
#
#   ./bootstrap.sh --no-install    only set up Epsilon, don't offer the install
#
set -euo pipefail

EPS_UUID=91e23279-79fe-4500-a491-1878037460cf
EPS_LABEL=Epsilon
MNT=/media/Epsilon
OPTS=rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,nofail
PRIVATE=$MNT/deuce/private
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NO_INSTALL=false; [[ ${1:-} == --no-install ]] && NO_INSTALL=true

G=$'\033[0;32m'; C=$'\033[0;36m'; Y=$'\033[1;33m'; R=$'\033[0;31m'; N=$'\033[0m'
log()  { echo "${G}[✓]${N} $*"; }
info() { echo "${C}[→]${N} $*"; }
warn() { echo "${Y}[!]${N} $*"; }
die()  { echo "${R}[✗]${N} $*"; exit 1; }

[[ $EUID -ne 0 ]] || die "Run as your user (it uses sudo where needed)."

if [[ "$(systemd-detect-virt 2>/dev/null || true)" != "none" ]]; then
  # Test VM: Primus shares /media/Epsilon/deuce read-only as 9p tag "epsilon".
  info "VM detected — mounting Primus's read-only Epsilon share"
  sudo mkdir -p "$MNT/deuce"
  mountpoint -q "$MNT/deuce" || sudo mount -t 9p -o trans=virtio,version=9p2000.L,ro epsilon "$MNT/deuce" \
    || die "Share not available — start the VM with rebuild/vm/vm.sh run"
else
  # ── find Epsilon ──
  uuid=""
  if [[ -e /dev/disk/by-uuid/$EPS_UUID ]]; then
    uuid=$EPS_UUID
  else
    warn "Epsilon's usual UUID not found — looking for a btrfs drive labelled '$EPS_LABEL'"
    mapfile -t hits < <(lsblk -rno UUID,LABEL,FSTYPE | awk -v l="$EPS_LABEL" '$2==l && $3=="btrfs" {print $1}')
    ((${#hits[@]} == 1)) || die "Found ${#hits[@]} btrfs drives labelled '$EPS_LABEL' — expected exactly 1. Check with: lsblk -f"
    uuid=${hits[0]}
  fi
  dev=$(readlink -f "/dev/disk/by-uuid/$uuid")
  info "Epsilon is $dev — $(lsblk -dno SIZE,MODEL "/dev/$(lsblk -no PKNAME "$dev")" 2>/dev/null | xargs), label $(lsblk -no LABEL "$dev")"

  # ── fstab ──
  if awk -v m="$MNT" '$1 !~ /^#/ && $2 == m' /etc/fstab | grep -q .; then
    log "$MNT already in /etc/fstab"
  else
    [[ -e /etc/fstab.bak-bootstrap ]] || sudo cp -a /etc/fstab /etc/fstab.bak-bootstrap
    printf 'UUID=%s   %s   btrfs   %s   0 0\n' "$uuid" "$MNT" "$OPTS" | sudo tee -a /etc/fstab >/dev/null
    log "added $MNT to /etc/fstab (backup: /etc/fstab.bak-bootstrap)"
  fi

  # ── mount ──
  if mountpoint -q "$MNT"; then log "$MNT already mounted"
  else
    sudo mkdir -p "$MNT"
    sudo systemctl daemon-reload
    sudo mount "$MNT" && log "mounted $MNT"
  fi
fi

# ── what's on it ──
[[ -d $MNT/deuce ]]        || die "$MNT/deuce not found — is this the right drive?"
[[ -d $PRIVATE/home ]]     && log "private backup found ($(cat "$PRIVATE/info/snapshot-date.txt" 2>/dev/null || echo 'date unknown'))" \
                           || warn "no private backup at $PRIVATE — install.sh needs it (run backup-private.sh on the old system)"
[[ -d $MNT/deuce/myarch2 ]] && log "myarch2 copy on Epsilon: $MNT/deuce/myarch2"

$NO_INSTALL && { log "Epsilon ready."; exit 0; }
echo
read -rp "Run the full install now (rebuild/install.sh, 30-60 min)? [Y/n] " a || a=n
[[ ${a,,} == n ]] && { echo "Later:  $HERE/rebuild/install.sh"; exit 0; }
exec "$HERE/rebuild/install.sh"
