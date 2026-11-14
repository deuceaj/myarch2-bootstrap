#!/usr/bin/env bash
# vm.sh — test VM for the rebuild scripts (QEMU/KVM, UEFI, 80G sparse disk).
#
#   ./vm.sh fetch-iso        download + verify the current Arch ISO (~1.3 GB)
#   ./vm.sh install          boot the Arch ISO (run archinstall inside)
#   ./vm.sh run              boot the installed VM
#   ./vm.sh save NAME        snapshot the VM disk (VM must be off)
#   ./vm.sh restore NAME     roll the disk back to a snapshot (VM must be off)
#   ./vm.sh list             list snapshots
#   ./vm.sh destroy          delete the VM disk + firmware vars
#   ./vm.sh type 'TEXT' [--enter]   type TEXT into the running VM (no copy/paste needed)
#   ./vm.sh mount-share      type the read-only share mount command into the VM
#
# Inside the VM, /media/Epsilon/deuce from Primus is shared READ-ONLY
# (mount tag "epsilon"), so install.sh can read myarch2 + the private backup
# without being able to change anything on the real drive.
set -euo pipefail
VMDIR=${VMDIR:-/media/Epsilon/vm/rebuild-test}
DISK=$VMDIR/disk.qcow2
VARS=$VMDIR/OVMF_VARS.4m.fd
ISO=$VMDIR/archlinux-x86_64.iso
QMP=$VMDIR/qmp.sock
HERE=$(cd "$(dirname "$0")" && pwd)
MOUNT_CMD='sudo mkdir -p /media/Epsilon/deuce && sudo mount -t 9p -o trans=virtio,version=9p2000.L,ro epsilon /media/Epsilon/deuce && ls /media/Epsilon/deuce/myarch2/rebuild' 
CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
MIRROR=https://geo.mirror.pkgbuild.com/iso/latest

need() { command -v qemu-system-x86_64 >/dev/null && [[ -f $CODE ]] \
         || { echo "Install first: sudo pacman -S --needed qemu-desktop edk2-ovmf"; exit 1; }; }
prep() {
  mkdir -p "$VMDIR"
  [[ -f $DISK ]] || qemu-img create -f qcow2 "$DISK" 80G
  [[ -f $VARS ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VARS"
}
boot() {
  local args=(
    -name rebuild-test -enable-kvm -machine q35 -cpu host -smp 6 -m 8G
    -drive "if=pflash,format=raw,readonly=on,file=$CODE"
    -drive "if=pflash,format=raw,file=$VARS"
    -drive "file=$DISK,if=virtio,cache=writeback,discard=unmap"
    -device virtio-vga-gl -display gtk,gl=on
    -device qemu-xhci -device usb-tablet
    -nic user,model=virtio-net-pci
    -virtfs local,path=/media/Epsilon/deuce,mount_tag=epsilon,security_model=none,readonly=on
    -qmp "unix:$QMP,server=on,wait=off"
  )
  exec qemu-system-x86_64 "${args[@]}" "$@"
}

case ${1:-} in
  fetch-iso)
    mkdir -p "$VMDIR"; cd "$VMDIR"
    curl -fL -o archlinux-x86_64.iso     "$MIRROR/archlinux-x86_64.iso"
    curl -fL -o archlinux-x86_64.iso.sig "$MIRROR/archlinux-x86_64.iso.sig"
    curl -fL -o sha256sums.txt           "$MIRROR/sha256sums.txt"
    grep ' archlinux-x86_64.iso$' sha256sums.txt | sha256sum -c -
    pacman-key -v archlinux-x86_64.iso.sig archlinux-x86_64.iso
    echo "ISO verified (checksum + Arch release signature)." ;;
  install) need; prep; [[ -f $ISO ]] || { echo "No ISO: ./vm.sh fetch-iso"; exit 1; }
           boot -cdrom "$ISO" -boot order=d ;;
  run)     need; prep; boot ;;
  save)    qemu-img snapshot -c "${2:?name}" "$DISK" && echo "saved snapshot '$2'" ;;
  restore) qemu-img snapshot -a "${2:?name}" "$DISK" && echo "disk rolled back to '$2'" ;;
  list)    qemu-img snapshot -l "$DISK" ;;
  type)    [[ -S $QMP ]] || { echo "VM not running (no $QMP)"; exit 1; }
           shift; python3 -I "$HERE/vm-type.py" "$QMP" "$@" ;;
  mount-share) python3 -I "$HERE/vm-type.py" "$QMP" "$MOUNT_CMD" --enter ;;
  destroy) read -rp "Delete $DISK and firmware vars? [y/N] " a; [[ ${a,,} == y ]] && rm -f "$DISK" "$VARS" ;;
  *) sed -n '2,15p' "$0"; exit 1 ;;
esac
