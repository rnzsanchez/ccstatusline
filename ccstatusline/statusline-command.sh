#!/usr/bin/env bash
# Claude Code status line
# Line 1: model effort account | folder • branch • worktree • PR • session
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

# Takes a Unix epoch (seconds)
compute_delta() {
  local epoch="$1"
  [[ "$epoch" =~ ^[0-9]+$ ]] || return
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
# One jq call; \x1f (not whitespace) keeps empty fields from collapsing in `read`
IFS=$'\x1f' read -r model dir used ctx_used ctx_total five_h seven_d five_h_reset seven_d_reset \
  sid session effort pr_num pr_url pr_state wt_name wt_git < <(jq -r '[
  .model.display_name, (.workspace.current_dir // .cwd), .context_window.used_percentage,
  .context_window.total_input_tokens, .context_window.context_window_size,
  .rate_limits.five_hour.used_percentage, .rate_limits.seven_day.used_percentage,
  .rate_limits.five_hour.resets_at, .rate_limits.seven_day.resets_at,
  .session_id, .session_name, .effort.level, .pr.number, .pr.url, .pr.review_state,
  .worktree.name, .workspace.git_worktree
] | map((. // "") | tostring | gsub("[\\n\\t\u001f]"; " ")) | join("\u001f")' <<< "$input")

# Strip "Claude " prefix and " context" suffix
model="${model#Claude }"
model="${model/ context/}"

dir_name=$(basename "$dir")

# Account key from the config dir; label shown only for non-default (.claude-work -> work)
acct_key=$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
acct=""
if [ "$acct_key" != ".claude" ]; then acct="${acct_key#.claude-}"; acct="${acct#.}"; fi

# ── Shared usage: sessions of one account show the newest rate_limits ─────────
# stdin rate_limits only update after a session's own API response. Fields that
# changed since this session last saw them are fresh and go to a per-account file.
# Cache lives in TMPDIR, never under the config dir (it is symlinked across accounts).
if [ -n "$sid" ]; then
  cache="${TMPDIR:-/tmp}/ccstatusline"
  mkdir -p -m 700 "$cache" 2>/dev/null
  seen="$cache/seen-$acct_key-$sid"
  usage="$cache/usage-$acct_key"
  now=$(date -u "+%s")
  rl="$five_h|$seven_d|$five_h_reset|$seven_d_reset"
  prev_rl=""
  [ -f "$seen" ] && read -r prev_rl < "$seen"
  if [ "$rl" != "|||" ] && [ "$rl" != "$prev_rl" ]; then
    echo "$rl" > "$seen"
    echo "$now|$rl" > "$usage.$$" && mv "$usage.$$" "$usage"
  fi
  [ -f "$usage" ] && IFS='|' read -r _ five_h seven_d five_h_reset seven_d_reset < "$usage"
  [ "${five_h_reset:-$now}" -le "$now" ] 2>/dev/null && five_h="" five_h_reset=""
  [ "${seven_d_reset:-$now}" -le "$now" ] 2>/dev/null && seven_d="" seven_d_reset=""
  touch "$seen" 2>/dev/null
  find "$cache" -name 'seen-*' -mtime +1 -delete 2>/dev/null
fi

# ── Git branch ───────────────────────────────────────────────────────────────
branch=""
if [ -n "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || \
           git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# ── Line 1: model effort account | folder • branch • worktree • PR • session ─
model_color="$blue"
case "$model" in *Opus*) model_color="$amber" ;; *Haiku*) model_color="$cyan" ;; esac

line1="${model_color}${model}${reset}"
[ -n "$effort" ] && line1+=" ${dim}${effort}${reset}"
[ -n "$acct" ] && line1+=" ${orange}${acct}${reset}"
line1+=" ${dim}|${reset} "
line1+="${cyan}${dir_name}${reset}"
[ -n "$branch" ] && line1+="${SEP}${magenta}${branch}${reset}"
wt="${wt_name:-$wt_git}"
[ -n "$wt" ] && line1+="${SEP}${dim}wt${reset} ${cyan}${wt}${reset}"
if [ -n "$pr_num" ]; then
  pr_seg="#${pr_num}${pr_state:+ $pr_state}"
  [ -n "$pr_url" ] && pr_seg=$(printf '\033]8;;%s\a%s\033]8;;\a' "$pr_url" "$pr_seg")
  line1+="${SEP}${amber}${pr_seg}${reset}"
fi
[ -n "$session" ] && line1+="${SEP}${dim}${session}${reset}"

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

  ctx_seg="${dim}ctx${reset} ${ctx_color}${ctx_pct}%${reset}"
  if [[ "$ctx_used" =~ ^[0-9]+$ && "$ctx_total" =~ ^[0-9]+$ ]] && [ "$ctx_total" -gt 0 ]; then
    ctx_seg+=" ${dim}($(( ctx_used / 1000 ))k/$(( ctx_total / 1000 ))k)${reset}"
  fi

  [ -n "$line2" ] && line2+=" ${dim}|${reset} ${ctx_seg}" || line2="${ctx_seg}"
fi

if [ -n "$line2" ]; then
  printf "%b\n" "$line2"
fi
