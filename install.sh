#!/usr/bin/env bash
# Installs claude-code-statusline into %USERPROFILE%\.claude (Windows + Git Bash).
#
#   bash install.sh
#
# What it does:
#   1. Downloads jq (official release, checksum-verified) to ~/.claude/bin/jq.exe if missing
#   2. Copies statusline.sh to ~/.claude/statusline.sh (backs up an existing one)
#   3. Sets "statusLine" in ~/.claude/settings.json (backs up first, keeps every other setting)
#   4. Renders a sample status line so you can see it works

set -euo pipefail

JQ_VERSION="1.8.1"
JQ_SHA256="23cb60a1354eed6bcc8d9b9735e8c7b388cd1fdcb75726b93bc299ef22dd9334"
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-windows-amd64.exe"
REFRESH_INTERVAL=60

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stamp="$(date +%Y%m%d-%H%M%S)"

if [[ -z "${USERPROFILE:-}" ]] || ! command -v cygpath &>/dev/null; then
  echo "This installer is for Windows with Git Bash. On macOS/Linux, see the manual steps in README.md." >&2
  exit 1
fi

claude_dir="$(cygpath -u "$USERPROFILE")/.claude"
bin_dir="$claude_dir/bin"
settings="$claude_dir/settings.json"
mkdir -p "$bin_dir"

# ── 1. jq ─────────────────────────────────────────────────────
jq_bin="$bin_dir/jq.exe"
if [[ ! -f "$jq_bin" ]]; then
  echo "Downloading jq ${JQ_VERSION} ..."
  curl -fsSL "$JQ_URL" -o "$jq_bin.tmp"
  actual="$(sha256sum "$jq_bin.tmp" | cut -d' ' -f1)"
  if [[ "$actual" != "$JQ_SHA256" ]]; then
    rm -f "$jq_bin.tmp"
    echo "jq checksum mismatch (got $actual). Aborting." >&2
    exit 1
  fi
  mv "$jq_bin.tmp" "$jq_bin"
  echo "  -> $jq_bin"
else
  echo "jq already present: $jq_bin"
fi

# Check settings.json parses before touching anything
jq_input=(-n)
if [[ -f "$settings" ]] && grep -q '[^[:space:]]' "$settings"; then   # an empty file counts as no settings
  if ! "$jq_bin" empty "$settings"; then
    echo "Could not parse $settings (is it valid JSON?). Nothing was changed." >&2
    exit 1
  fi
  jq_input=("$settings")
fi

# ── 2. statusline.sh ──────────────────────────────────────────
if [[ -f "$claude_dir/statusline.sh" ]]; then
  cp -p "$claude_dir/statusline.sh" "$claude_dir/statusline.sh.bak-$stamp"
  echo "Backed up existing statusline.sh -> statusline.sh.bak-$stamp"
fi
cp "$src/statusline.sh" "$claude_dir/statusline.sh"
echo "Installed $claude_dir/statusline.sh"

# ── 3. settings.json ──────────────────────────────────────────
# Claude Code runs the command through Windows, so use Windows-style paths:
#   "C:\Program Files\Git\bin\bash.exe" "C:/Users/<you>/.claude/statusline.sh"
bash_win="$(cygpath -w /)bin\\bash.exe"
script_win="$(cygpath -m "$USERPROFILE")/.claude/statusline.sh"
cmd="\"$bash_win\" \"$script_win\""

if [[ -f "$settings" ]]; then
  cp -p "$settings" "$settings.bak-$stamp"
  echo "Backed up settings.json -> settings.json.bak-$stamp"
fi

# Merge into any existing statusLine block so extra keys (padding, etc.) survive
SL_CMD="$cmd" SL_REFRESH="$REFRESH_INTERVAL" "$jq_bin" \
  '.statusLine = ((.statusLine // {}) + {type: "command", command: env.SL_CMD, refreshInterval: (env.SL_REFRESH | tonumber)})' \
  "${jq_input[@]}" > "$settings.tmp"
mv "$settings.tmp" "$settings"
echo "Updated $settings:"
"$jq_bin" '.statusLine' "$settings"

# ── 4. Smoke test ─────────────────────────────────────────────
now="$(date +%s)"
sample="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\
\"context_window\":{\"used_percentage\":42,\"context_window_size\":200000,\"total_input_tokens\":84000},\
\"cost\":{\"total_cost_usd\":1.23,\"total_duration_ms\":65000},\
\"rate_limits\":{\"five_hour\":{\"used_percentage\":23,\"resets_at\":$((now + 7980))},\
\"seven_day\":{\"used_percentage\":41,\"resets_at\":$((now + 273600))}},\
\"workspace\":{\"current_dir\":\"$(cygpath -m "$PWD")\"}}"

echo
echo "Sample output:"
echo "$sample" | bash "$claude_dir/statusline.sh"
echo
echo
echo "Done. Restart Claude Code to see the new status line."
