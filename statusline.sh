#!/usr/bin/env bash
# ~/.claude/statusline.sh — Claude Code session status line
#
# Two lines of output:
#   Line 1: ◆ model ·effort │ gradient bar percent tokens │ elapsed │ rate limits
#   Line 2: ⎇branch* │ +added/-removed │ folder │ worktree/agent tag
#
# Environment variables:
#   CLAUDE_STATUSLINE_ASCII=1     plain ASCII only
#   CLAUDE_STATUSLINE_NERDFONT=1  Nerd Font icons
#   CLAUDE_STATUSLINE_POWERLINE=1 Powerline separators (defaults to NERDFONT)
#   COLORTERM=truecolor|24bit     set by the terminal; enables the truecolor gradient

set -euo pipefail

# bundled jq (Windows has no system jq)
PATH="$HOME/.claude/bin:$PATH"

# ═══════════════════════════════════════════════════════════════
# Environment
# ═══════════════════════════════════════════════════════════════

USE_ASCII="${CLAUDE_STATUSLINE_ASCII:-0}"
USE_NERDFONT="${CLAUDE_STATUSLINE_NERDFONT:-0}"
USE_POWERLINE="${CLAUDE_STATUSLINE_POWERLINE:-$USE_NERDFONT}"
USE_TRUECOLOR=0
if [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]]; then
  USE_TRUECOLOR=1
fi

# ═══════════════════════════════════════════════════════════════
# Colours and symbols
# ═══════════════════════════════════════════════════════════════

ESC=$'\033'
RST=$'\033[0m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
GRAY=$'\033[90m'
DIM=$'\033[2m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'

# Anthropic brand purple (#7266EA)
if (( USE_TRUECOLOR )); then
  PURPLE=$'\033[38;2;114;102;234m'
else
  PURPLE=$'\033[35m'
fi

# dir path: light blue (#8FB8FF), bright blue when truecolor is unavailable
if (( USE_TRUECOLOR )); then
  DIRCOL=$'\033[38;2;143;184;255m'
else
  DIRCOL=$'\033[94m'
fi

# Symbol sets
if [[ "$USE_ASCII" == "1" ]]; then
  S_BRAND="<>"
  S_BRANCH=">"
  S_WARN="!"
  S_TIME=""
  S_EFFORT="E:"
  S_PACE="^"
  SEP=" | "
elif [[ "$USE_NERDFONT" == "1" ]]; then
  S_BRAND="◆"
  S_BRANCH=" "
  S_WARN=" 󰀦"
  S_TIME="󰔟 "
  S_EFFORT=" "
  S_PACE="▲"
  if [[ "$USE_POWERLINE" == "1" ]]; then
    SEP="  "
  else
    SEP=" │ "
  fi
else
  S_BRAND="◆"
  S_BRANCH="⎇"
  S_WARN=" ⚠"
  S_TIME=""
  S_EFFORT="·"
  S_PACE="▲"
  if [[ "$USE_POWERLINE" == "1" ]]; then
    SEP="  "
  else
    SEP=" │ "
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Fallback output
# ═══════════════════════════════════════════════════════════════

fallback_prompt() {
  printf '%s' "${GRAY}${1:-─}${RST}"
  exit 0
}

command -v jq &>/dev/null || fallback_prompt "─ │ jq not found"

# ═══════════════════════════════════════════════════════════════
# Read the JSON (one jq call)
# ═══════════════════════════════════════════════════════════════

input=$(cat)

parsed=$(echo "$input" | jq -r '
  (.model.display_name // ""),
  (.context_window.used_percentage // 0 | tostring),
  (.workspace.current_dir // "." | (sub(".*[/\\\\]"; "") | select(. != "")) // .),
  (.worktree.branch // ""),
  (.rate_limits.five_hour.used_percentage // -1 | tostring),
  (.rate_limits.seven_day.used_percentage // -1 | tostring),
  (.agent.name // ""),
  (.workspace.current_dir // "."),
  (.cost.total_lines_added // 0 | tostring),
  (.cost.total_lines_removed // 0 | tostring),
  (.cost.total_duration_ms // 0 | tostring),
  (.context_window.context_window_size // 0 | tostring),
  (.worktree.name // ""),
  (.context_window.total_input_tokens // 0 | tostring),
  (.effort.level // ""),
  (.rate_limits.five_hour.resets_at // 0 | tostring),
  (.rate_limits.seven_day.resets_at // 0 | tostring),
  "END"
' 2>/dev/null | tr -d '\r') || fallback_prompt "─ │ parse error"

{
  IFS= read -r model_name
  IFS= read -r ctx_pct
  IFS= read -r dir
  IFS= read -r branch
  IFS= read -r rate5h
  IFS= read -r rate7d
  IFS= read -r agent_name
  IFS= read -r cwd_full
  IFS= read -r lines_add
  IFS= read -r lines_rm
  IFS= read -r duration_ms
  IFS= read -r ctx_size
  IFS= read -r wt_name
  IFS= read -r used_tokens
  IFS= read -r effort_level
  IFS= read -r reset5h
  IFS= read -r reset7d
  IFS= read -r _sentinel
} <<< "$parsed"

# ═══════════════════════════════════════════════════════════════
# Model
# ═══════════════════════════════════════════════════════════════

model="${model_name:-─}"

# ═══════════════════════════════════════════════════════════════
# Reasoning effort — hidden when the model doesn't support it (the JSON then
# has no effort field). The value is the level in effect for this turn, after
# any silent downgrade.
# ═══════════════════════════════════════════════════════════════

effort_section=""
case "${effort_level:-}" in
  low)    effort_color="$GRAY" ;;
  medium) effort_color="$GREEN" ;;
  high)   effort_color="$YELLOW" ;;
  xhigh)  effort_color="$MAGENTA" ;;
  max)    effort_color="$RED" ;;
  *)      effort_color="" ;;
esac
if [[ -n "$effort_color" ]]; then
  effort_section=" ${effort_color}${S_EFFORT}${effort_level}${RST}"
fi

# ═══════════════════════════════════════════════════════════════
# Context bar
# ═══════════════════════════════════════════════════════════════

pct_int=${ctx_pct%.*}
pct_int=${pct_int:-0}
if (( pct_int < 0 )); then pct_int=0; fi
if (( pct_int > 100 )); then pct_int=100; fi

bar_filled=$(( pct_int / 10 ))
if (( bar_filled > 10 )); then bar_filled=10; fi

# Gradient (truecolor): green → yellow → orange → red
GRAD_R=(46 116 186 241 239 236 233 231 211 192)
GRAD_G=(204 195 186 196 161 126 101 76 66 57)
GRAD_B=(113 89 64 15 24 34 44 60 50 43)

bar=""
if [[ "$USE_ASCII" == "1" ]]; then
  # ASCII mode
  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then bar+="#"; else bar+="-"; fi
  done
elif (( USE_TRUECOLOR )); then
  # Truecolor gradient: each cell gets its own colour
  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then
      bar+="${ESC}[38;2;${GRAD_R[$i]};${GRAD_G[$i]};${GRAD_B[$i]}m█"
    else
      bar+="${ESC}[38;2;60;60;60m░"
    fi
  done
  bar+="${RST}"
else
  # 16-colour fallback: one colour for the whole bar, picked by percentage
  if (( pct_int >= 90 )); then bar_color="$RED"
  elif (( pct_int >= 70 )); then bar_color="$YELLOW"
  else bar_color="$GREEN"; fi

  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then bar+="█"; else bar+="░"; fi
  done
  bar="${bar_color}${bar}${RST}"
fi

# Percentage and token count colour (same thresholds as the bar)
if (( pct_int >= 90 )); then pct_color="$RED"
elif (( pct_int >= 70 )); then pct_color="$YELLOW"
else pct_color="$GREEN"; fi

# Warning sign
ctx_warn=""
if (( pct_int >= 90 )); then ctx_warn="${RED}${S_WARN}${RST}"; fi

# Context window size (only when the model's display_name doesn't already include it)
ctx_size_int=${ctx_size:-0}
ctx_label=""
if [[ "$model" != *context* && "$model" != *Context* ]]; then
  if (( ctx_size_int >= 1000000 )); then ctx_label=" ${GRAY}1M${RST}"
  elif (( ctx_size_int >= 200000 )); then ctx_label=" ${GRAY}200k${RST}"
  fi
fi

# Tokens used (same basis as used_percentage: input + cache reads/writes, no output)
fmt_tokens() {
  local t=$1 whole frac
  if (( t < 1000 )); then
    printf '%d' "$t"
  elif (( t < 1000000 )); then
    whole=$(( t / 1000 ))
    frac=$(( (t % 1000) / 100 ))
    if (( whole >= 100 || frac == 0 )); then
      printf '%dk' "$whole"
    else
      printf '%d.%dk' "$whole" "$frac"
    fi
  else
    whole=$(( t / 1000000 ))
    frac=$(( (t % 1000000) / 100000 ))
    if (( frac == 0 )); then
      printf '%dM' "$whole"
    else
      printf '%d.%dM' "$whole" "$frac"
    fi
  fi
}

used_tokens_int=${used_tokens:-0}
tok_label=""
if (( used_tokens_int > 0 )); then
  if (( ctx_size_int > 0 )); then
    # window size known: show used/total, which replaces the size-only label
    tok_label=" ${pct_color}$(fmt_tokens "$used_tokens_int")/$(fmt_tokens "$ctx_size_int")${RST}"
    ctx_label=""
  else
    tok_label=" ${pct_color}$(fmt_tokens "$used_tokens_int")${RST}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Elapsed time (hidden at 0)
# ═══════════════════════════════════════════════════════════════

dur_ms=${duration_ms:-0}
dur_section=""
if (( dur_ms > 0 )); then
  dur_sec=$((dur_ms / 1000))
  dur_h=$((dur_sec / 3600))
  dur_min=$((dur_sec % 3600 / 60))
  dur_s=$((dur_sec % 60))
  # past an hour: "3h05m" (seconds no longer matter)
  if (( dur_h > 0 )); then
    printf -v dur_txt '%dh%02dm' "$dur_h" "$dur_min"
    dur_section="${SEP}${GRAY}${S_TIME}${dur_txt}${RST}"
  # hidden while it still formats as 0m0s (dur_ms can be a few hundred ms when a session starts)
  elif (( dur_min > 0 || dur_s > 0 )); then
    dur_section="${SEP}${GRAY}${S_TIME}${dur_min}m${dur_s}s${RST}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Git branch and dirty flag (cached)
# ═══════════════════════════════════════════════════════════════

# One cache file per folder, so Claude Code windows open in different repos
# don't show each other's branch. Lines: written-at epoch, folder, branch, dirty.
# Kept under the user's home: in a shared /tmp another user could create the
# file first (a symlink to overwrite, or fake content to print).
GIT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
GIT_CACHE_MAX_AGE=5
now_epoch=${EPOCHSECONDS:-$(date +%s)}

git_branch="${branch:-}"
dirty=""

if [[ -n "${cwd_full:-}" && -d "${cwd_full:-}" ]]; then
  git_cache="$GIT_CACHE_DIR/git-${cwd_full//[^A-Za-z0-9._-]/_}"
  cache_ts="" cache_dir="" cached_br="" cached_dt=""
  if [[ -f "$git_cache" ]]; then
    { IFS= read -r cache_ts; IFS= read -r cache_dir; IFS= read -r cached_br; IFS= read -r cached_dt; } < "$git_cache" || true
  fi

  # the folder check catches two paths that map to the same file name
  if [[ "$cache_dir" != "$cwd_full" || ! "$cache_ts" =~ ^[0-9]+$ ]] || (( now_epoch - cache_ts > GIT_CACHE_MAX_AGE )); then
    cached_br="" cached_dt=""
    # one call gives the branch, the HEAD sha and the dirty state (untracked files count)
    if git_out=$(git -C "$cwd_full" --no-optional-locks -c core.useBuiltinFSMonitor=false status --porcelain=v2 --branch 2>/dev/null); then
      head="" oid=""
      while IFS= read -r line; do
        case "$line" in
          "# branch.oid "*)  oid=${line#"# branch.oid "} ;;
          "# branch.head "*) head=${line#"# branch.head "} ;;
          "#"*) ;;
          ?*) cached_dt="*"; break ;;
        esac
      done <<< "$git_out"
      if [[ "$head" == "(detached)" ]]; then cached_br=${oid:0:7}; else cached_br=$head; fi
    fi
    [[ -d "$GIT_CACHE_DIR" ]] || mkdir -p "$GIT_CACHE_DIR" 2>/dev/null || true
    printf '%s\n%s\n%s\n%s\n' "$now_epoch" "$cwd_full" "$cached_br" "$cached_dt" 2>/dev/null > "$git_cache" || true
  fi

  if [[ -z "$git_branch" ]]; then git_branch="$cached_br"; fi
  dirty="$cached_dt"
fi

# ═══════════════════════════════════════════════════════════════
# Lines added/removed (hidden at 0)
# ═══════════════════════════════════════════════════════════════

lines_add=${lines_add:-0}
lines_rm=${lines_rm:-0}
lines_section=""
if (( lines_add > 0 || lines_rm > 0 )); then
  lines_section="${GREEN}+${lines_add}${RST}/${RED}-${lines_rm}${RST}"
fi

# ═══════════════════════════════════════════════════════════════
# Rate limits (only when Claude Code sends them)
# ═══════════════════════════════════════════════════════════════

rate_section=""
rate5h_int=${rate5h%.*}; rate5h_int=${rate5h_int:-0}
rate7d_int=${rate7d%.*}; rate7d_int=${rate7d_int:-0}
reset5h_int=${reset5h%.*}; reset5h_int=${reset5h_int:-0}
reset7d_int=${reset7d%.*}; reset7d_int=${reset7d_int:-0}

# time left until a window resets, into REPLY: "3d4h" / "2h05m" / "45m" / "<1m"
fmt_left() {
  local d=$(( $1 / 86400 )) h=$(( $1 % 86400 / 3600 )) m=$(( $1 % 3600 / 60 ))
  if (( d > 0 )); then printf -v REPLY '%dd%dh' "$d" "$h"
  elif (( h > 0 )); then printf -v REPLY '%dh%02dm' "$h" "$m"
  elif (( m > 0 )); then REPLY="${m}m"
  else REPLY="<1m"; fi
}

# Appends one window to rate_parts, e.g. "5h:23% (2h13m)". Red from 80%.
# Pace marker: more of the limit is used than of the window has passed, so
# at this rate the limit runs out before the reset (yellow below 80%). Not
# judged in the first 10% of a window, where one big request skews the rate.
add_rate() {
  local label=$1 used=$2 resets_at=$3 window=$4
  local color="$GRAY" pace="" left_txt="" left elapsed
  if (( used < 0 )); then return 0; fi
  left=$(( resets_at - now_epoch ))
  if (( resets_at > 0 && left > 0 )); then
    fmt_left "$left"
    left_txt=" ($REPLY)"
    elapsed=$(( window - left ))
    if (( elapsed * 10 >= window && used * window > elapsed * 100 )); then
      pace="$S_PACE"
      color="$YELLOW"
    fi
  fi
  if (( used >= 80 )); then color="$RED"; fi
  if [[ -n "$rate_parts" ]]; then rate_parts+=" "; fi
  rate_parts+="${color}${label}:${used}%${pace}${left_txt}${RST}"
}

rate_parts=""
add_rate 5h "$rate5h_int" "$reset5h_int" $(( 5 * 3600 ))
add_rate 7d "$rate7d_int" "$reset7d_int" $(( 7 * 86400 ))
if [[ -n "$rate_parts" ]]; then
  rate_section="${SEP}${rate_parts}"
fi

# ═══════════════════════════════════════════════════════════════
# Line 1
# ═══════════════════════════════════════════════════════════════

line1="${PURPLE}${S_BRAND}${RST} ${CYAN}${model}${RST}${effort_section}"
line1+="${SEP}${bar} ${pct_color}${pct_int}%${RST}${ctx_warn}${ctx_label}${tok_label}"
line1+="${dur_section}"
line1+="${rate_section}"

# ═══════════════════════════════════════════════════════════════
# Line 2
# ═══════════════════════════════════════════════════════════════

parts=()
if [[ -n "$git_branch" ]]; then
  parts+=("${GRAY}${S_BRANCH}${git_branch}${dirty}${RST}")
fi
if [[ -n "$lines_section" ]]; then
  parts+=("${lines_section}")
fi
parts+=("${DIRCOL}${dir}${RST}")

# Agent / worktree tag (only outside the main session)
if [[ -n "${wt_name:-}" ]]; then
  parts+=("${YELLOW}⚙ worktree:${wt_name}${RST}")
elif [[ -n "${agent_name:-}" ]]; then
  parts+=("${YELLOW}⚙ ${agent_name}${RST}")
fi

line2=""
for i in "${!parts[@]}"; do
  if (( i > 0 )); then
    line2+="${SEP}"
  fi
  line2+="${parts[$i]}"
done

# ═══════════════════════════════════════════════════════════════
# Output
# ═══════════════════════════════════════════════════════════════

# two lines only; Claude Code draws its own input prompt
printf '%s\n%s' "$line1" "$line2"
