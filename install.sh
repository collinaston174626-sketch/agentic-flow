#!/usr/bin/env bash
# Installs the "flow" skill for every supported agent found on this machine.
# Usage: ./install.sh [--dry-run]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/skills/flow"
dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
home="${FLOW_HOME:-$HOME}"
run() { if [ $dry = 1 ]; then echo "would: $*"; else "$@"; fi; }

installed=0
# Standard Agent Skills locations: <dir>/skills/flow/SKILL.md
for base in .claude .codex .agents .gemini .cursor; do
  if [ -d "$home/$base" ]; then
    run mkdir -p "$home/$base/skills"
    run rm -rf "$home/$base/skills/flow"
    run cp -R "$src" "$home/$base/skills/flow"
    echo "skill installed: $home/$base/skills/flow"
    installed=1
  fi
done

# Claude Code: native sub-agents with pinned models, generated from the roles.
if [ -d "$home/.claude" ]; then
  run mkdir -p "$home/.claude/agents"
  gen() { # role model tools description
    local out="$home/.claude/agents/flow-$1.md"
    if [ $dry = 1 ]; then echo "would: write $out"; return; fi
    { printf -- '---\nname: flow-%s\ndescription: %s\nmodel: %s\n' "$1" "$4" "$2"
      [ -n "$3" ] && printf 'tools: %s\n' "$3"
      printf -- '---\n\n'; cat "$src/roles/$1.md"; } > "$out"
    echo "agent installed: $out"
  }
  gen planner fable "Read, Glob, Grep, Bash, Write, WebSearch, WebFetch" "Flow stage 1: plans the task into PLAN.md. Spawned only by the flow orchestrator."
  gen executor opus "" "Flow stage 2: executes PLAN.md and writes SUMMARY_r<N>.md. Spawned only by the flow orchestrator."
  gen verificator opus "Read, Glob, Grep, Bash, Write" "Flow stage 3: adversarially verifies the result and writes VERIFICATION_r<N>.md. Spawned only by the flow orchestrator."
fi

if [ $installed = 0 ]; then
  echo "No supported agent directory found in $home (.claude .codex .agents .gemini .cursor)."
  echo "Copy skills/flow/ into your agent's skills directory manually."
  exit 1
fi
echo "Done. Restart your agent and say: use flow <your task>  (Claude Code: /flow <task>)"
