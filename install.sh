#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
INSTALL_DIR="$CLAUDE_DIR/ccstatusline"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "ccstatusline installer"
echo "─────────────────────────────────────────────"

# ── Dependency check ──────────────────────────────────────────────────────────
MISSING=0
check_dep() {
  if ! command -v "$1" &>/dev/null; then
    printf "  [missing] %-12s %s\n" "$1" "$2"
    MISSING=1
  else
    printf "  [ok]      %s\n" "$1"
  fi
}

echo ""
echo "Checking dependencies..."
check_dep bash     "(already running)"
check_dep jq       "brew install jq"
check_dep curl     "included on macOS"
check_dep python3  "brew install python3 or Xcode CLT"
check_dep git      "brew install git"
check_dep security "macOS Keychain — required for rate-limit display"

if [ "$MISSING" -eq 1 ]; then
  echo ""
  echo "Install the missing dependencies above, then re-run install.sh"
  exit 1
fi

# ── Copy scripts ──────────────────────────────────────────────────────────────
echo ""
echo "Installing scripts to $INSTALL_DIR ..."

mkdir -p "$INSTALL_DIR"

install_script() {
  local src="$1" dest="$2"
  cp "$src" "$dest"
  chmod +x "$dest"
  printf "  [copied]  %s\n" "$dest"
}

install_script "$SCRIPT_DIR/ccstatusline/statusline-command.sh" "$INSTALL_DIR/statusline-command.sh"
install_script "$SCRIPT_DIR/ccstatusline/fetch-usage.sh"        "$INSTALL_DIR/fetch-usage.sh"

# ── Merge settings.json ───────────────────────────────────────────────────────
echo ""
echo "Merging $SETTINGS ..."

python3 - "$SETTINGS" <<'PYEOF'
import json, sys, copy, os

settings_path = sys.argv[1]

WANTED_STATUS_LINE = {
    "type": "command",
    "command": "bash ~/.claude/ccstatusline/statusline-command.sh"
}

WANTED_PRE_TOOL_USE = [
    {
        "matcher": "WebSearch|WebFetch",
        "hooks": [{"type": "command",
                   "command": "echo \"Current date/time: $(date '+%Y-%m-%d %H:%M:%S %Z')\""}]
    },
    {
        "matcher": "",
        "hooks": [{"type": "command",
                   "command": "bash ~/.claude/ccstatusline/fetch-usage.sh > /dev/null 2>&1 &"}]
    }
]

def cmds(block):
    return frozenset(h["command"] for h in block.get("hooks", []) if "command" in h)

def already_present(existing_list, candidate):
    candidate_cmds = cmds(candidate)
    return any(cmds(e) == candidate_cmds for e in existing_list)

try:
    with open(settings_path) as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}

if "statusLine" not in settings:
    settings["statusLine"] = WANTED_STATUS_LINE

hooks = settings.setdefault("hooks", {})

existing_pre = hooks.setdefault("PreToolUse", [])
for candidate in WANTED_PRE_TOOL_USE:
    if not already_present(existing_pre, candidate):
        existing_pre.append(copy.deepcopy(candidate))

os.makedirs(os.path.dirname(os.path.abspath(settings_path)), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("  [merged]  " + settings_path)
PYEOF

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────"
echo "  Installation complete."
echo "  Restart Claude Code for changes to take effect."
echo "─────────────────────────────────────────────"
