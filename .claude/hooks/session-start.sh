#!/bin/bash
set -euo pipefail

# Only run in Claude Code cloud sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Install graphify (knowledge-graph skill, used via /graphify)
if ! command -v graphify >/dev/null 2>&1; then
  pip install --quiet graphifyy
fi

if [ ! -f "$HOME/.claude/skills/graphify/SKILL.md" ]; then
  graphify install
fi
