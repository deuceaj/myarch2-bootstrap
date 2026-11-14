#!/usr/bin/env bash
#
# backup.sh — refresh the PUBLIC config snapshot (configs/) from the live
# system, then run the PRIVATE backup (rebuild/backup-private.sh).
#
#   ./backup.sh              public snapshot + private backup
#   ./backup.sh --public     public snapshot only (no sudo)
#
# Only the apps allow-listed in .gitignore are refreshed, each one on its own
# (rsync --delete scoped to that app's folder). Nothing else under configs/ is
# touched, and nothing is ever wiped wholesale.
# (The old version did `rm -rf configs/` and re-copied a DMS-era list, which
#  deleted umbriel/spicetify/ai-usagebar from the snapshot on 2026-11-13.)
#
# After running: review `git diff` for anything private, then commit.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

G=$'\033[0;32m'; C=$'\033[0;36m'; Y=$'\033[1;33m'; N=$'\033[0m'
log()  { echo "${G}[✓]${N} $*"; }
info() { echo "${C}[→]${N} $*"; }
warn() { echo "${Y}[!]${N} $*"; }

COMMON=(--exclude='*.bak*' --exclude='*.backup-*' --exclude='*~')

# app | extra rsync excludes (generated or third-party files, per .gitignore notes)
snap() {
  local app=$1; shift
  local src=~/.config/$app dest=configs/.config/$app
  [[ -d $src ]] || { warn "not present: ~/.config/$app"; return; }
  mkdir -p "$dest"
  # --delete-excluded also clears generated/third-party files left in the
  # snapshot by older copies (they'd otherwise match the allow-list).
  rsync -a --delete --delete-excluded "${COMMON[@]}" "$@" "$src/" "$dest/"
  log "$app"
}

info "Public snapshot → configs/ (allow-listed apps only)"
snap umbriel     --exclude='/noctalia.toml'
snap noctalia    --exclude='/plugins/'
snap ai-usagebar
snap nvim        --exclude='/lua/matugen.lua'
snap kitty
snap cava        --exclude='/themes/noctalia'
mkdir -p configs/.config/spicetify
cp -a ~/.config/spicetify/config-xpui.ini configs/.config/spicetify/ && log "spicetify (config-xpui.ini only)"

echo
git --no-pager diff --stat -- configs/ || true
echo
warn "Review before committing (public repo):  git diff -- configs/"

[[ ${1:-} == --public ]] && exit 0
echo
info "Private backup → /media/Epsilon/deuce/private"
exec ./rebuild/backup-private.sh
