# Primus rebuild — fresh Arch → umbriel + noctalia, the way it runs today

| Script | Where / when | What it does |
|---|---|---|
| `backup-private.sh` | on the **working** Primus, before wiping (and after big changes) | snapshots settings, secrets, `/etc` bits and Steam config into `/media/Epsilon/deuce/private` (mode 700, never committed) |
| `install.sh` | fresh install, COSMIC session, terminal | packages, system files, kernel params, drives, login screen, home settings, services, firewall, default apps |
| `first-login.sh` | once, inside umbriel after the reboot | checks monitor names, restores Steam library + GE-Proton, runs doctor, lists sign-ins |
| `doctor.sh` | any time | read-only health check, ✓/✗ per item |
| `vm/vm.sh` | on Primus | test VM for all of the above |

Package lists: `pkgs/pacman.txt`, `pkgs/aur.txt`. Home paths backed up: `home-manifest.txt`.
Re-run one step of the installer: `./install.sh greeter` (steps: preflight pacman_setup
install_pacman install_aur system_files boot_config drives greeter home_restore umbriel_compat services firewall defaults).

## Before wiping
1. `./backup-private.sh` (asks for sudo once).
2. noctalia greeter: Settings → Security → Noctalia Greeter → Sync Now, *then* run the backup, so the greeter look is captured.
3. **Windows Part 2 done** (Windows has its own EFI partition on sda) — otherwise
   archinstall's "wipe" formats the EFI partition that Windows boots from.
4. `passwd` if not done.

## archinstall choices
- **Disk: ONLY the Crucial P3 500 GB (CT500P3PSSD8).**
  **Never** the Samsung 980 1 TB (Epsilon — all your files) or the WD Blue 1 TB (Steam).
  Two of them are "1 TB" — go by the model name.
- Wipe → best-effort, **btrfs**, default subvolumes, zstd compression
- Bootloader **GRUB** (snapshot menu + Windows need it), no UKI
- Swap: zram · Hostname: Primus · User: **deuce** (sudo) · Timezone America/New_York
- Profile: **Desktop → Cosmic**, graphics: AMD/ATI open-source · Audio: pipewire
- Kernel: linux · Network: NetworkManager · Optional repos: **multilib**

## After archinstall (real machine)
```bash
sudo mkdir -p /media/Epsilon && sudo mount UUID=91e23279-79fe-4500-a491-1878037460cf /media/Epsilon
/media/Epsilon/deuce/myarch2/rebuild/install.sh
# reboot → noctalia login screen → Umbriel
/media/Epsilon/deuce/myarch2/rebuild/first-login.sh
```

## Test in the VM first
On Primus:
```bash
sudo pacman -S --needed qemu-desktop edk2-ovmf
cd /media/Epsilon/deuce/myarch2/rebuild/vm
./vm.sh fetch-iso          # ~1.3 GB, checksum + signature verified
./vm.sh install            # boots the ISO: run archinstall (disk = the only virtio disk)
./vm.sh run                # boot the fresh install, log in to COSMIC once, power off
./vm.sh save fresh         # snapshot: you can roll back here and re-test any time
./vm.sh run
```
Inside the VM (COSMIC terminal):
```bash
sudo mkdir -p /media/Epsilon/deuce
sudo mount -t 9p -o trans=virtio,version=9p2000.L,ro epsilon /media/Epsilon/deuce
/media/Epsilon/deuce/myarch2/rebuild/install.sh
# reboot, log in via the noctalia greeter (Umbriel), then:
/media/Epsilon/deuce/myarch2/rebuild/first-login.sh
```
The share is **read-only**: the VM can read myarch2 and the private backup but cannot change
anything on Epsilon. Fans, real disks and the Windows entry are skipped in the VM (shown as –).
To re-test from scratch: power off, `./vm.sh restore fresh`, `./vm.sh run`.

## Troubleshooting
- **archinstall: "GPGME error: No data / invalid or corrupted database", core/extra only ~3 KiB** —
  it picked a broken mirror. Exit archinstall, then
  `echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > /etc/pacman.d/mirrorlist && pacman -Sy`,
  re-run archinstall and leave the mirror *region* empty (still enable multilib). Seen in the VM test 2026-11-13.
- **Locked out after a greeter change** — Ctrl+Alt+F2, log in, `greeter-restore-dms`
  (or restore `/etc/greetd/config.toml.bak-rebuild`) and **reboot**. Never `systemctl restart greetd` from a session.

## What stays manual (by design)
Sign-ins (Mullvad, Tailscale, Steam, Spotify, NordPass, pCloud, Notion, Discord, Zoom, Claude),
greeter Sync Now, `spicetify backup apply`. `first-login.sh` prints the checklist.
