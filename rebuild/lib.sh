# lib.sh — shared helpers for the rebuild scripts. Source it, don't run it.

REBUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_DIR="${PRIVATE_DIR:-/media/Epsilon/deuce/private}"
EPSILON="${EPSILON:-/media/Epsilon}"
LOG_DIR="${HOME}/rebuild-logs"
mkdir -p "$LOG_DIR"

G=$'\033[0;32m'; C=$'\033[0;36m'; Y=$'\033[1;33m'; R=$'\033[0;31m'; B=$'\033[1m'; N=$'\033[0m'
log()     { echo "${G}[✓]${N} $*"; }
info()    { echo "${C}[→]${N} $*"; }
warn()    { echo "${Y}[!]${N} $*"; }
err()     { echo "${R}[✗]${N} $*"; }
section() { echo; echo "${B}${C}══ $* ══${N}"; }

# Failures are collected, not fatal: one broken package or file must not stop
# the whole rebuild. Everything is listed again in the summary at the end.
FAILURES=()
fail() { err "$*"; FAILURES+=("$*"); }

# Running inside the test VM? Hardware-only steps (fans, real disks, Windows
# boot entry) are skipped there and reported as "skipped (VM)".
IS_VM=false
if [[ "$(systemd-detect-virt 2>/dev/null || true)" != "none" ]]; then IS_VM=true; fi

# Keep sudo's timestamp fresh during long AUR builds so it never stops halfway
# to ask for the password again. Uses the normal sudo timestamp; nothing is
# written to /etc/sudoers.
sudo_keepalive() {
    sudo -v || { err "sudo failed"; exit 1; }
    ( while true; do sudo -n -v 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

# Read a package/list file: strip comments and blank lines.
read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^[[:space:]]*$' || true; }

# Copy a file into place as root, keeping a one-time backup of what was there.
install_root_file() {  # src dest mode
    local src=$1 dest=$2 mode=${3:-0644}
    [[ -f "$src" ]] || { fail "missing in private backup: $src"; return 1; }
    if [[ -e "$dest" && ! -e "${dest}.bak-rebuild" ]]; then sudo cp -a "$dest" "${dest}.bak-rebuild"; fi
    sudo install -D -m "$mode" "$src" "$dest" && log "installed $dest"
}

print_summary() {
    section "Summary"
    if ((${#FAILURES[@]} == 0)); then
        log "No failures."
    else
        err "${#FAILURES[@]} item(s) need attention:"
        printf '   - %s\n' "${FAILURES[@]}"
    fi
}
