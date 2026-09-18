#!/usr/bin/env bash
#
# bootstrap.sh — The ONE script you copy from Epsilon to a fresh CachyOS install.
#
# Workflow:
#   1. Fresh CachyOS install → reboot
#   2. Mount Epsilon manually: sudo mount /dev/sdX1 /mnt
#   3. Copy this script:       cp /mnt/deuce/myarch2/bootstrap.sh ~/
#   4. Unmount:                 sudo umount /mnt
#   5. Run:                     chmod +x ~/bootstrap.sh && ~/bootstrap.sh
#   6. After reboot, run:       /media/Epsilon/deuce/myarch2/post-install-gui.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }
info()  { echo -e "${CYAN}[→]${NC} $1"; }

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  deuce — CachyOS Bootstrap${NC}"
echo -e "${CYAN}  Sets up drives, credentials, and fstab${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo ""

USERNAME="deuce"
HOME_DIR="/home/${USERNAME}"

# ─── SMB Credentials ──────────────────────────────────────────

info "Setting up SMB credentials for network drives..."

mkdir -p "${HOME_DIR}/.local"

read -rp "Enter SMB username: " smb_user
read -rsp "Enter SMB password: " smb_pass
echo ""

cat > "${HOME_DIR}/.local/.smbcredentials" <<EOF
username=${smb_user}
password=${smb_pass}
EOF
chmod 600 "${HOME_DIR}/.local/.smbcredentials"
log "SMB credentials saved to ${HOME_DIR}/.local/.smbcredentials"

read -rp "Do you have a separate Retroludus SMB credential? (y/N): " has_retro
if [[ "${has_retro,,}" == "y" ]]; then
    read -rp "Enter Retroludus SMB username: " retro_user
    read -rsp "Enter Retroludus SMB password: " retro_pass
    echo ""
    cat > "${HOME_DIR}/.local/.smbcredentials_Retroludas" <<EOF
username=${retro_user}
password=${retro_pass}
EOF
    chmod 600 "${HOME_DIR}/.local/.smbcredentials_Retroludas"
    log "Retroludus credentials saved"
fi

# ─── Mount Points ─────────────────────────────────────────────

info "Creating mount points..."

MOUNT_DIRS=(
    /media/Epsilon
    /media/Arena
    /media/Nexus
    /media/Theatrum
    /media/Retroludus
)

for dir in "${MOUNT_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        sudo mkdir -p "$dir"
        log "Created $dir"
    else
        warn "$dir already exists"
    fi
done

sudo chown -R "${USERNAME}:${USERNAME}" /media/Epsilon /media/Arena /media/Nexus /media/Theatrum /media/Retroludus
log "Ownership set on mount points"

# ─── Install cifs-utils ───────────────────────────────────────

info "Installing cifs-utils for network drive support..."
sudo pacman -S --noconfirm --needed cifs-utils ntfs-3g ntfsprogs
log "cifs-utils, ntfs-3g, and ntfsprogs installed"

# ─── Fstab ────────────────────────────────────────────────────

info "Backing up /etc/fstab..."
sudo cp /etc/fstab /etc/fstab.bak
log "Backup saved to /etc/fstab.bak"

info "Appending drive entries to /etc/fstab..."

# Check if we've already added our entries
if grep -q "# deuce-myarch drives" /etc/fstab; then
    warn "fstab entries already present — skipping"
else
    sudo bash -c 'cat >> /etc/fstab' <<'FSTAB'

# deuce-myarch drives
# ─── Network Drives (CIFS) ───
//192.168.2.101/Nexus/                      /media/Nexus       cifs    vers=2.0,credentials=/home/deuce/.local/.smbcredentials,iocharset=utf8,gid=1000,uid=1000,file_mode=0777,dir_mode=0777,mfsymlinks,noauto,x-systemd.automount   0 0
//192.168.2.101/Theta                       /media/Theatrum    cifs    vers=2.0,credentials=/home/deuce/.local/.smbcredentials,iocharset=utf8,gid=1000,uid=1000,file_mode=0777,dir_mode=0777,mfsymlinks,noauto,x-systemd.automount   0 0
//192.168.2.3/Retroludus/                   /media/Retroludus  cifs    vers=2.0,credentials=/home/deuce/.local/.smbcredentials_Retroludas,iocharset=utf8,gid=1000,uid=1000,file_mode=0777,dir_mode=0777,mfsymlinks,noauto,x-systemd.automount   0 0

# ─── Local Drives (NTFS) ───
UUID=1B6DB9CB19B7FAA7                       /media/Arena       ntfs3   defaults,nofail,uid=1000,gid=1001,umask=0022,nodev,x-gvfs-show   0 0
UUID=1ADF3DE94D9C6F52                       /media/Epsilon     ntfs3   uid=1000,gid=1000,force,iocharset=utf8,nofail 0 0
FSTAB
    log "fstab entries added"
fi

echo ""
cat /etc/fstab
echo ""

# ─── Fix dirty NTFS volumes ────────────────────────────────────
# ntfs3 refuses to mount an NTFS volume left "dirty" by an unclean
# Windows shutdown/hibernation. ntfsfix clears it, but the -d flag
# is required — without it, ntfsfix reports success and leaves the
# dirty flag untouched.

fix_dirty_ntfs() {
    local uuid="$1" label="$2"
    local dev="/dev/disk/by-uuid/${uuid}"
    [[ -e "$dev" ]] || return 0
    sudo ntfsfix -d "$dev" &>/dev/null \
        && log "${label}: cleared dirty NTFS flag" \
        || warn "${label}: ntfsfix failed on ${dev}"
}

info "Checking Epsilon/Arena for dirty NTFS flag..."
fix_dirty_ntfs 1ADF3DE94D9C6F52 Epsilon
fix_dirty_ntfs 1B6DB9CB19B7FAA7 Arena

# ─── Mount Everything ─────────────────────────────────────────

info "Mounting all drives..."
sudo systemctl daemon-reload
sudo mount -a 2>/dev/null || warn "Some drives may not be available (network drives mount on demand)"
log "Drives mounted"

# ─── Verify Epsilon ──────────────────────────────────────────

echo ""
if [[ -d "/media/Epsilon/deuce/myarch2" ]]; then
    log "Epsilon mounted and myarch2 found!"
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Bootstrap complete!${NC}"
    echo -e "${GREEN}  ${NC}"
    echo -e "${GREEN}  Next step — open the post-install GUI:${NC}"
    echo -e "${CYAN}  /media/Epsilon/deuce/myarch2/post-install-gui.sh${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
else
    warn "Epsilon mounted but myarch2 not found at /media/Epsilon/deuce/myarch2"
    warn "You may need to check the Epsilon drive contents."
    echo ""
    echo -e "${YELLOW}  After verifying Epsilon, run:${NC}"
    echo -e "${CYAN}  /media/Epsilon/deuce/myarch2/post-install-gui.sh${NC}"
fi

echo ""
