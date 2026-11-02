#!/usr/bin/env bash
# Agentic Flow installer for Claude Code.
# Installs the /flow slash command, its three sub-agents and the context-meter script:
#   commands/flow.md              -> ~/.claude/commands/flow.md
#   agents/flow-{planner,executor,verificator}.md -> ~/.claude/agents/
#   scripts/flow_ctx.py           -> ~/.claude/scripts/flow_ctx.py
#
# Usage: ./install.sh [--dry-run] [--uninstall] [--no-backup] [-h|--help]
#   --dry-run    show what would be done, change nothing
#   --uninstall  remove the installed files (backups are kept)
#   --no-backup  overwrite existing files without saving a backup copy
# Environment:
#   FLOW_HOME    home directory to install into (default: $HOME)
set -euo pipefail

here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
home="${FLOW_HOME:-$HOME}"
dest="$home/.claude"
backup_dir="$dest/.flow-backup/$(date +%Y%m%d-%H%M%S)-$$"

dry=0; uninstall=0; backup=1; backed_up=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)   dry=1 ;;
    --uninstall) uninstall=1 ;;
    --no-backup) backup=0 ;;
    -h|--help)   sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 64 ;;
  esac
done

# source (relative to repo) : target (relative to ~/.claude) : mode
FILES=(
  "commands/flow.md:commands/flow.md:644"
  "agents/flow-planner.md:agents/flow-planner.md:644"
  "agents/flow-executor.md:agents/flow-executor.md:644"
  "agents/flow-verificator.md:agents/flow-verificator.md:644"
  "scripts/flow_ctx.py:scripts/flow_ctx.py:755"
)

say() { printf '%s\n' "$*"; }
run() { if [ "$dry" = 1 ]; then say "  would: $*"; else "$@"; fi; }
did() { if [ "$dry" = 1 ]; then printf 'would %s\n' "$*"; else printf '%s\n' "$*"; fi; }

# Copy the CONTENT (symlinks dereferenced) of ~/.claude/<rel> into the backup dir.
save_backup() {
  local rel="$1"
  [ "$backup" = 1 ] || return 0
  run mkdir -p "$(dirname "$backup_dir/$rel")"
  run cp -RpL "$dest/$rel" "$backup_dir/$rel"
  backed_up=1
}

if stat -c '%a' / >/dev/null 2>&1; then mode_of() { stat -c '%a' "$1"; }   # GNU
else mode_of() { stat -f '%Lp' "$1"; }; fi                                # BSD/macOS

# The legacy (v1) release installed Flow as a skill: ~/.claude/skills/flow/{SKILL.md,roles/}.
# A skill and a command with the same name collide, so the v1 skill is moved to the backup.
remove_legacy_skill() {
  local rel="skills/flow"
  [ -f "$dest/$rel/SKILL.md" ] && [ -f "$dest/$rel/roles/planner.md" ] || return 0
  grep -q '^name: *flow *$' "$dest/$rel/SKILL.md" 2>/dev/null || {
    say "note: $dest/$rel exists but is not the Agentic Flow v1 skill - left untouched."
    say "      A skill named 'flow' may shadow the /flow command; rename or remove it yourself."
    return 0
  }
  say "legacy v1 skill found: $dest/$rel (superseded by the /flow command)"
  if [ "$backup" = 1 ]; then
    run mkdir -p "$backup_dir/skills"
    run mv "$dest/$rel" "$backup_dir/$rel"
    backed_up=1
    did "move to backup: $backup_dir/$rel"
  else
    run rm -r "$dest/$rel"
    did "remove: $dest/$rel"
  fi
}

# ---------------------------------------------------------------- uninstall
if [ "$uninstall" = 1 ]; then
  removed=0
  for entry in "${FILES[@]}"; do
    IFS=: read -r _src rel _mode <<<"$entry"
    if [ -e "$dest/$rel" ] || [ -L "$dest/$rel" ]; then
      [ -e "$dest/$rel" ] && save_backup "$rel"
      run rm -f "$dest/$rel"
      did "remove: $dest/$rel"
      removed=$((removed + 1))
    fi
  done
  [ "$removed" = 0 ] && say "Nothing to remove in $dest."
  [ "$backed_up" = 1 ] && [ "$dry" = 0 ] && say "Backup: $backup_dir"
  say "Done. Restart Claude Code."
  exit 0
fi

# ------------------------------------------------------------------ install
for entry in "${FILES[@]}"; do
  IFS=: read -r src _rel _mode <<<"$entry"
  [ -f "$here/$src" ] || { echo "Missing source file: $here/$src (run from a full checkout)" >&2; exit 66; }
done

if [ ! -d "$dest" ]; then
  say "Note: $dest does not exist yet (Claude Code never started on this account?) - creating it."
  run mkdir -p "$dest"
fi

command -v python3 >/dev/null 2>&1 || \
  say "Warning: python3 not found - scripts/flow_ctx.py (context meter) needs it; the protocol falls back to an inline check."

remove_legacy_skill

installed=0; unchanged=0
for entry in "${FILES[@]}"; do
  IFS=: read -r src rel mode <<<"$entry"
  target="$dest/$rel"
  if [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$here/$src" "$target" \
     && [ "$(mode_of "$target")" = "$mode" ]; then
    say "up to date: $target"; unchanged=$((unchanged + 1)); continue
  fi
  run mkdir -p "$(dirname "$target")"
  if [ -e "$target" ]; then save_backup "$rel"; fi
  # Replace, never write through: a symlinked target (dotfiles) must not have its source overwritten.
  run rm -f "$target"
  run cp "$here/$src" "$target"
  run chmod "$mode" "$target"
  did "install: $target"
  installed=$((installed + 1))
done

if [ "$dry" = 1 ]; then
  say ""
  say "Dry run: $installed file(s) would be installed, $unchanged already up to date. Nothing changed."
  exit 0
fi

# self-check
for entry in "${FILES[@]}"; do
  IFS=: read -r src rel mode <<<"$entry"
  cmp -s "$here/$src" "$dest/$rel" && [ "$(mode_of "$dest/$rel")" = "$mode" ] || {
    echo "Self-check FAILED for $dest/$rel" >&2; exit 1; }
done

say ""
say "Agentic Flow: $installed file(s) installed, $unchanged already up to date."
[ "$backed_up" = 1 ] && say "Previous versions saved to: $backup_dir"
say "Restart Claude Code, then run:  /flow <your task>"
