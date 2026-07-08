#!/usr/bin/env bash
# Claude Code status line
# Line 1: model | folder • branch
# Line 2: 5h X% (time_left) • 7d X% (time_left) | ctx X% (tokens)

input=$(cat)

# ── Colors ───────────────────────────────────────────────────────────────────
blue='\033[38;2;97;175;239m'
amber='\033[38;2;229;192;123m'
cyan='\033[38;2;86;182;194m'
orange='\033[38;2;255;176;85m'
yellow='\033[38;2;230;200;0m'
red='\033[38;2;235;87;87m'
magenta='\033[38;2;198;120;221m'
dim='\033[2m'
reset='\033[0m'

SEP=" ${dim}•${reset} "

# ── Helpers ───────────────────────────────────────────────────────────────────

# Accepts Unix epoch integer or ISO 8601 string
to_epoch() {
  local raw="$1"
  [ -z "$raw" ] && return
  [[ "$raw" =~ ^[0-9]+$ ]] && echo "$raw" && return
  local clean
  clean=$(echo "$raw" | sed 's/\.[0-9]*//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//' | sed 's/Z$//')
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" "+%s" 2>/dev/null
}

compute_delta() {
  local epoch="$1"
  [ -z "$epoch" ] && return
  local diff days hours minutes
  diff=$(( epoch - $(date -u "+%s") ))
  [ "$diff" -le 0 ] && echo "now" && return
  days=$(( diff / 86400 ))
  hours=$(( (diff % 86400) / 3600 ))
  minutes=$(( (diff % 3600) / 60 ))
  if   [ "$days"  -gt 0 ]; then echo "${days}d ${hours}h"
  elif [ "$hours" -gt 0 ]; then echo "${hours}h ${minutes}m"
  else echo "${minutes}m"; fi
}

# ── Extract data ─────────────────────────────────────────────────────────────
model=$(echo "$input" | jq -r '.model.display_name // ""')
dir=$(echo "$input"   | jq -r '.workspace.current_dir // .cwd // ""')
used=$(echo "$input"  | jq -r '.context_window.used_percentage // empty')

# Strip "Claude " prefix and " context" suffix
model="${model#Claude }"
model="${model/ context/}"

dir_name=$(basename "$dir")

# ── Usage cache ───────────────────────────────────────────────────────────────
CACHE_FILE="/tmp/.claude_usage_cache"
five_h="" seven_d="" five_h_reset="" seven_d_reset=""
if [ -f "$CACHE_FILE" ]; then
  five_h=$(sed -n '1p' "$CACHE_FILE")
  seven_d=$(sed -n '2p' "$CACHE_FILE")
  five_h_reset=$(sed -n '3p' "$CACHE_FILE")
  seven_d_reset=$(sed -n '4p' "$CACHE_FILE")
else
  bash ~/.claude/ccstatusline/fetch-usage.sh > /dev/null 2>&1 &
fi

# Fall back to rate_limits in JSON
[ -z "$five_h" ]        && five_h=$(echo "$input"        | jq -r '.rate_limits.five_hour.used_percentage // empty')
[ -z "$seven_d" ]       && seven_d=$(echo "$input"       | jq -r '.rate_limits.seven_day.used_percentage // empty')
[ -z "$five_h_reset" ]  && five_h_reset=$(echo "$input"  | jq -r '.rate_limits.five_hour.resets_at // empty')
[ -z "$seven_d_reset" ] && seven_d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Normalise to epoch integers
five_h_reset=$(to_epoch "$five_h_reset")
seven_d_reset=$(to_epoch "$seven_d_reset")

# ── Git branch ───────────────────────────────────────────────────────────────
branch=""
if [ -n "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || \
           git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# ── Line 1: model | folder • branch ──────────────────────────────────────────
model_color="$blue"
case "$model" in *Opus*) model_color="$amber" ;; *Haiku*) model_color="$cyan" ;; esac

line1="${model_color}${model}${reset}"
line1+=" ${dim}|${reset} "
line1+="${cyan}${dir_name}${reset}"
[ -n "$branch" ] && line1+="${SEP}${magenta}${branch}${reset}"

# ── Plugin badges (dynamic) ──────────────────────────────────────────────────
# Each installed plugin may ship a `*-statusline.sh`. We run it and append its
# output verbatim, so the badge looks exactly how that plugin's author intended
# (its own colors, its own gating — it prints nothing when inactive). No plugin
# names or colors live here; installing a badge-capable plugin makes its badge
# appear with zero edits to this file.
PLUGIN_REGISTRY="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
if [ -f "$PLUGIN_REGISTRY" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r plugin_path; do
    [ -d "$plugin_path" ] || continue
    sl_script=$(find "$plugin_path" -maxdepth 4 -type f -name '*-statusline.sh' 2>/dev/null | head -1)
    [ -n "$sl_script" ] || continue
    badge_out=$(bash "$sl_script" </dev/null 2>/dev/null)
    [ -n "$badge_out" ] && line1+="${SEP}${badge_out}"
  done < <(jq -r '.plugins | to_entries | sort_by(.key)[] | .value[-1].installPath // empty' "$PLUGIN_REGISTRY" 2>/dev/null)
fi

printf "%b\n" "$line1"

# ── Line 2: 5h • 7d | ctx ────────────────────────────────────────────────────
line2=""

if [ -n "$five_h" ]; then
  f=$(printf "%.0f" "$five_h")
  if   [ "$f" -ge 80 ]; then pct_color="$red"
  elif [ "$f" -ge 50 ]; then pct_color="$yellow"
  else pct_color="$cyan"; fi

  seg="${pct_color}5h ${f}%${reset}"
  if [ -n "$five_h_reset" ]; then
    delta=$(compute_delta "$five_h_reset")
    [ -n "$delta" ] && seg+=" ${dim}(${delta})${reset}"
  fi
  line2="${seg}"
fi

if [ -n "$seven_d" ]; then
  s=$(printf "%.0f" "$seven_d")

  seg="${cyan}7d ${s}%${reset}"
  if [ -n "$seven_d_reset" ]; then
    delta=$(compute_delta "$seven_d_reset")
    [ -n "$delta" ] && seg+=" ${dim}(${delta})${reset}"
  fi
  [ -n "$line2" ] && line2+="${SEP}${seg}" || line2="${seg}"
fi

if [ -n "$used" ]; then
  ctx_pct=$(printf "%.0f" "$used")
  if   [ "$ctx_pct" -ge 80 ]; then ctx_color="$red"
  elif [ "$ctx_pct" -ge 50 ]; then ctx_color="$orange"
  else ctx_color="$cyan"; fi

  ctx_used=$(echo "$input" | jq -r '(
    (.context_window.current_usage.cache_read_input_tokens   // 0) +
    (.context_window.current_usage.cache_creation_input_tokens // 0) +
    (.context_window.current_usage.input_tokens              // 0) +
    (.context_window.current_usage.output_tokens             // 0)
  )' 2>/dev/null)
  ctx_total=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)

  ctx_seg="${dim}ctx${reset} ${ctx_color}${ctx_pct}%${reset}"
  if [ -n "$ctx_used" ] && [ -n "$ctx_total" ] && [ "$ctx_total" -gt 0 ] 2>/dev/null; then
    ctx_seg+=" ${dim}($(( ctx_used / 1000 ))k/$(( ctx_total / 1000 ))k)${reset}"
  fi

  [ -n "$line2" ] && line2+=" ${dim}|${reset} ${ctx_seg}" || line2="${ctx_seg}"
fi

[ -n "$line2" ] && printf "%b\n" "$line2"
