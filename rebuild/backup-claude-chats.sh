#!/usr/bin/env bash
# backup-claude-chats.sh — copy every Claude Code / Claude desktop chat into the
# PRIVATE folder on Epsilon (chats can contain passwords and personal details).
#
#   <private>/claude-chats/
#     local/claude-projects/        ~/.claude/projects (all transcripts, *.jsonl)
#     local/desktop/                ~/.config/Claude session lists, agent-mode
#                                   sessions, scratch workspaces, SSH remote state
#     remote-<name>/claude-projects/  ~/.claude/projects pulled from each SSH
#                                   remote the desktop app uses (VPS, Kodus)
#
# Copies only (never deletes from the source). Remotes that can't be reached
# without a password are skipped and reported. Cloud sessions live on
# Anthropic's servers (claude.ai/code) and aren't on this computer.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

DEST="$PRIVATE_DIR/claude-chats"
mkdir -p "$DEST"/local/desktop
chmod 700 "$PRIVATE_DIR"

section "Claude chats (local) → $DEST/local"
rsync -a ~/.claude/projects/ "$DEST/local/claude-projects/" && \
  log "transcripts: $(find "$DEST/local/claude-projects" -name '*.jsonl' | wc -l) files"
for d in claude-code-sessions local-agent-mode-sessions scratch-workspaces claude-ssh-remote; do
  [[ -d ~/.config/Claude/$d ]] && rsync -a ~/.config/Claude/$d "$DEST/local/desktop/" && log "desktop: $d"
done
for f in ssh_configs.json ssh_worktree_locations.json config.json; do
  [[ -f ~/.config/Claude/$f ]] && cp -a ~/.config/Claude/$f "$DEST/local/desktop/"
done

section "Claude chats on SSH remotes"
# name|user@host — from ~/.config/Claude/ssh_configs.json
python3 -I -c '
import json, os, re
d = json.load(open(os.path.expanduser("~/.config/Claude/ssh_configs.json")))
for c in d.get("configs", []):
    name = re.sub(r"[^A-Za-z0-9_-]+", "-", c.get("name", "remote")).strip("-").lower()
    print(name + "|" + c["sshHost"])
' 2>/dev/null > "$DEST/.remotes"
# Read from a file (not a pipe) so ssh can't swallow the list and fail() counts.
# tar over ssh: works even where the remote has no rsync (the VPS doesn't).
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8)
while IFS='|' read -r name host; do
  if timeout 15 "${SSH[@]}" "$host" 'test -d ~/.claude/projects' </dev/null 2>/dev/null; then
    out="$DEST/remote-$name"; mkdir -p "$out/claude-projects"
    if "${SSH[@]}" "$host" 'tar -C ~/.claude -cf - projects' </dev/null | tar -C "$out" --transform 's,^projects,claude-projects,' -xf -; then
      log "$name ($host): $(find "$out/claude-projects" -name '*.jsonl' | wc -l) transcripts"
    else
      fail "$name ($host): copy failed"
    fi
  else
    fail "$name ($host): not reachable without a password — skipped"
  fi
done < "$DEST/.remotes"
rm -f "$DEST/.remotes"

chmod -R go-rwx "$DEST"
log "Claude chats: $(du -sh "$DEST" | cut -f1) at $DEST"
print_summary
