#!/usr/bin/env bash
# ~/.claude/statusline.sh — Claude Code session status line (aesthetic edition)
#
# 三行輸出：
#   第一行：◆ 模型 │ 漸層進度條 百分比 │ 時間 │ 速率限制
#   第二行：⎇分支* │ +增/-減 │ 目錄
#   第三行：❯ 提示符（顏色跟上下文用量連動）
#
# 環境變數：
#   CLAUDE_STATUSLINE_ASCII=1     退回純 ASCII
#   CLAUDE_STATUSLINE_NERDFONT=1  啟用 Nerd Font 圖示
#   CLAUDE_STATUSLINE_POWERLINE=1 啟用 Powerline 分隔符（預設跟隨 NERDFONT）
#   COLORTERM=truecolor|24bit     系統自動設定，啟用真彩色漸層

set -euo pipefail

# bundled jq (Windows has no system jq)
PATH="$HOME/.claude/bin:$PATH"

# ═══════════════════════════════════════════════════════════════
# 環境偵測
# ═══════════════════════════════════════════════════════════════

USE_ASCII="${CLAUDE_STATUSLINE_ASCII:-0}"
USE_NERDFONT="${CLAUDE_STATUSLINE_NERDFONT:-0}"
USE_POWERLINE="${CLAUDE_STATUSLINE_POWERLINE:-$USE_NERDFONT}"
USE_TRUECOLOR=0
if [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]]; then
  USE_TRUECOLOR=1
fi

# ═══════════════════════════════════════════════════════════════
# 色彩與符號
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

# Anthropic 品牌紫 (#7266EA)
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

# 符號集
if [[ "$USE_ASCII" == "1" ]]; then
  S_BRAND="<>"
  S_BRANCH=">"
  S_WARN="!"
  S_PROMPT=">"
  S_TIME=""
  S_EFFORT="E:"
  S_PACE="^"
  SEP=" | "
elif [[ "$USE_NERDFONT" == "1" ]]; then
  S_BRAND="◆"
  S_BRANCH=" "
  S_WARN=" 󰀦"
  S_PROMPT="❯"
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
  S_PROMPT="❯"
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
# 降級輸出
# ═══════════════════════════════════════════════════════════════

fallback_prompt() {
  printf '%s' "${GRAY}${1:-─}${RST}"
  exit 0
}

command -v jq &>/dev/null || fallback_prompt "─ │ jq not found"

# ═══════════════════════════════════════════════════════════════
# 讀取 JSON（單次 jq）
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
# 模型
# ═══════════════════════════════════════════════════════════════

model="${model_name:-─}"

# ═══════════════════════════════════════════════════════════════
# 推理力度（effort）— 模型不支援時 JSON 無此欄位，自動隱藏
# 值為當回合實際生效的等級（已套用靜默降級）
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
# 上下文進度條
# ═══════════════════════════════════════════════════════════════

pct_int=${ctx_pct%.*}
pct_int=${pct_int:-0}
if (( pct_int < 0 )); then pct_int=0; fi
if (( pct_int > 100 )); then pct_int=100; fi

bar_filled=$(( pct_int / 10 ))
if (( bar_filled > 10 )); then bar_filled=10; fi

# 漸層色（真彩色）：綠 → 黃 → 橘 → 紅
GRAD_R=(46 116 186 241 239 236 233 231 211 192)
GRAD_G=(204 195 186 196 161 126 101 76 66 57)
GRAD_B=(113 89 64 15 24 34 44 60 50 43)

bar=""
if [[ "$USE_ASCII" == "1" ]]; then
  # ASCII 模式
  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then bar+="#"; else bar+="-"; fi
  done
elif (( USE_TRUECOLOR )); then
  # 真彩色漸層：每格獨立上色
  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then
      bar+="${ESC}[38;2;${GRAD_R[$i]};${GRAD_G[$i]};${GRAD_B[$i]}m█"
    else
      bar+="${ESC}[38;2;60;60;60m░"
    fi
  done
  bar+="${RST}"
else
  # ANSI 退回：依整體百分比選色
  if (( pct_int >= 90 )); then bar_color="$RED"
  elif (( pct_int >= 70 )); then bar_color="$YELLOW"
  else bar_color="$GREEN"; fi

  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then bar+="█"; else bar+="░"; fi
  done
  bar="${bar_color}${bar}${RST}"
fi

# 百分比文字顏色（跟進度條整體色一致）
if (( pct_int >= 90 )); then pct_color="$RED"
elif (( pct_int >= 70 )); then pct_color="$YELLOW"
else pct_color="$GREEN"; fi

# 警告符號
ctx_warn=""
if (( pct_int >= 90 )); then ctx_warn="${RED}${S_WARN}${RST}"; fi

# 上下文視窗大小（僅在 model display_name 不包含 context 資訊時才顯示）
ctx_size_int=${ctx_size:-0}
ctx_label=""
if [[ "$model" != *context* && "$model" != *Context* ]]; then
  if (( ctx_size_int >= 1000000 )); then ctx_label=" ${GRAY}1M${RST}"
  elif (( ctx_size_int >= 200000 )); then ctx_label=" ${GRAY}200k${RST}"
  fi
fi

# 已用 token 數（與 used_percentage 同基準：input + cache 讀寫，不含 output）
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
    # 視窗大小已知：顯示 已用/總量，並取代原本單獨的大小標籤
    tok_label=" ${pct_color}$(fmt_tokens "$used_tokens_int")/$(fmt_tokens "$ctx_size_int")${RST}"
    ctx_label=""
  else
    tok_label=" ${pct_color}$(fmt_tokens "$used_tokens_int")${RST}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# 經過時間（零值智慧隱藏）
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
  # 格式化後仍為 0m0s 就不顯示（session 啟動初期 dur_ms 可能是幾百毫秒）
  elif (( dur_min > 0 || dur_s > 0 )); then
    dur_section="${SEP}${GRAY}${S_TIME}${dur_min}m${dur_s}s${RST}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Git 分支與髒標記（帶快取）
# ═══════════════════════════════════════════════════════════════

# One cache file per folder, so Claude Code windows open in different repos
# don't show each other's branch. Lines: written-at epoch, folder, branch, dirty.
GIT_CACHE_MAX_AGE=5
now_epoch=${EPOCHSECONDS:-$(date +%s)}

git_branch="${branch:-}"
dirty=""

if [[ -n "${cwd_full:-}" && -d "${cwd_full:-}" ]]; then
  git_cache="/tmp/claude-statusline-git-${cwd_full//[^A-Za-z0-9._-]/_}"
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
    printf '%s\n%s\n%s\n%s\n' "$now_epoch" "$cwd_full" "$cached_br" "$cached_dt" 2>/dev/null > "$git_cache" || true
  fi

  if [[ -z "$git_branch" ]]; then git_branch="$cached_br"; fi
  dirty="$cached_dt"
fi

# ═══════════════════════════════════════════════════════════════
# 行數增減（零值智慧隱藏）
# ═══════════════════════════════════════════════════════════════

lines_add=${lines_add:-0}
lines_rm=${lines_rm:-0}
lines_section=""
if (( lines_add > 0 || lines_rm > 0 )); then
  lines_section="${GREEN}+${lines_add}${RST}/${RED}-${lines_rm}${RST}"
fi

# ═══════════════════════════════════════════════════════════════
# 速率限制（條件顯示）
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
# 動態提示符（顏色跟上下文用量連動）
# ═══════════════════════════════════════════════════════════════

if (( pct_int >= 90 )); then prompt_color="$RED"
elif (( pct_int >= 70 )); then prompt_color="$YELLOW"
else prompt_color="$GREEN"; fi

# ═══════════════════════════════════════════════════════════════
# 組裝第一行
# ═══════════════════════════════════════════════════════════════

line1="${PURPLE}${S_BRAND}${RST} ${CYAN}${model}${RST}${effort_section}"
line1+="${SEP}${bar} ${pct_color}${pct_int}%${RST}${ctx_warn}${ctx_label}${tok_label}"
line1+="${dur_section}"
line1+="${rate_section}"

# ═══════════════════════════════════════════════════════════════
# 組裝第二行
# ═══════════════════════════════════════════════════════════════

parts=()
if [[ -n "$git_branch" ]]; then
  parts+=("${GRAY}${S_BRANCH}${git_branch}${dirty}${RST}")
fi
if [[ -n "$lines_section" ]]; then
  parts+=("${lines_section}")
fi
parts+=("${DIRCOL}${dir}${RST}")

# Agent / Worktree 指示器（僅在非主 session 時顯示）
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
# 輸出
# ═══════════════════════════════════════════════════════════════

# 只輸出兩行（Claude Code 有自己的輸入提示符，不需要我們的 ❯）
printf '%s\n%s' "$line1" "$line2"
