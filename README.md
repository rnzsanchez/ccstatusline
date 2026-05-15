# ccstatusline

A custom Claude Code status line that shows your current model, working folder, git branch, rate-limit usage, and context window pressure.

## What It Shows

**Line 1** — model, folder, branch:
```
Sonnet 4.6  |  myproject  •  main
```

**Line 2** — rate limits and context usage:
```
5h 34% (3h 22m)  •  7d 12% (5d 8h)  |  ctx 41% (82k/200k)
```

Color coding:
- Model: Opus = amber, Haiku = cyan, others = blue
- Usage percentages: cyan below 50%, yellow at 50–79%, red at 80%+

## Prerequisites

- **macOS** — `fetch-usage.sh` uses the macOS Keychain (`security` command) to read your Claude OAuth token
- **Claude Code** — installs its OAuth credentials into the Keychain on first login
- **jq** — `brew install jq`
- **curl** — included on macOS
- **python3** — included on macOS 12+; otherwise `brew install python3`
- **git** — Xcode CLT or `brew install git`

## Quick Install

```bash
git clone https://github.com/rnzsanchez/ccstatusline.git
cd ccstatusline
bash install.sh
```

Then restart Claude Code.

## Manual Install

1. Copy the scripts to `~/.claude/ccstatusline/`:
   ```bash
   mkdir -p ~/.claude/ccstatusline
   cp ccstatusline/statusline-command.sh ~/.claude/ccstatusline/
   cp ccstatusline/fetch-usage.sh ~/.claude/ccstatusline/
   chmod +x ~/.claude/ccstatusline/*.sh
   ```

2. Add the following to `~/.claude/settings.json` (merge with any existing content):
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/ccstatusline/statusline-command.sh"
     },
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "WebSearch|WebFetch",
           "hooks": [{"type": "command", "command": "echo \"Current date/time: $(date '+%Y-%m-%d %H:%M:%S %Z')\""}]
         },
         {
           "matcher": "",
           "hooks": [{"type": "command", "command": "bash ~/.claude/ccstatusline/fetch-usage.sh > /dev/null 2>&1 &"}]
         }
       ]
     }
   }
   ```

3. Restart Claude Code.

## Configuration Notes

**Rate-limit data** — `fetch-usage.sh` reads your OAuth access token from the macOS Keychain entry named `Claude Code-credentials`, which is populated automatically when you sign in to Claude Code. Results are cached at `/tmp/.claude_usage_cache` for 15 minutes, so the displayed percentages update at that cadence.

## Uninstall

```bash
rm -rf ~/.claude/ccstatusline
```

Then remove the `statusLine` key and the ccstatusline hook entries from `~/.claude/settings.json`, and restart Claude Code.
