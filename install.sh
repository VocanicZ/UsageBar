#!/usr/bin/env bash
# UsageBar installer.
#
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/VocanicZ/UsageBar/main/install.sh | bash
#
# With options:
#   curl -fsSL .../install.sh | bash -s -- --scope user --cache 60 --bar-len 8
#
# Flags:
#   --scope          project | user | system   where to write the statusLine setting
#   --cache N        usage cache TTL seconds (default 60)
#   --bar-len N      meter length in glyphs (default 8)
#   --reserve N      columns kept clear at far right for Claude's own status (default 0)
#   --width-fallback N  terminal width to assume when it can't be probed (default 120)
#   --help
#
# UsageBar shares one status line with ContextBar via a small composer at
# ~/.claude/statusbar/compose.sh + registry ~/.claude/statusbar/parts.json.
# Context is always LEFT, usage always RIGHT, regardless of install order.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/VocanicZ/UsageBar/main"
USAGE_DIR="$HOME/.claude/usagebar"
USAGE_DST="$USAGE_DIR/usagebar.sh"
BAR_DIR="$HOME/.claude/statusbar"
COMPOSE_DST="$BAR_DIR/compose.sh"
REG="$BAR_DIR/parts.json"
CTX_SCRIPT="$HOME/.claude/contextbar/statusline.sh"

SCOPE=""; CACHE="60"; BAR_LEN="8"; RESERVE="0"; WIDTH_FALLBACK="120"

die() { echo "usagebar: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)          SCOPE="${2:-}"; shift 2 ;;
    --cache)          CACHE="${2:-}"; shift 2 ;;
    --bar-len)        BAR_LEN="${2:-}"; shift 2 ;;
    --reserve)        RESERVE="${2:-}"; shift 2 ;;
    --width-fallback) WIDTH_FALLBACK="${2:-}"; shift 2 ;;
    --help|-h) sed -n '2,22p' "$0" 2>/dev/null || true; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

command -v jq   >/dev/null 2>&1 || die "jq is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

TTY=""; [ -e /dev/tty ] && TTY=/dev/tty
ask() {
  local prompt="$1" def="$2" ans=""
  if [ -n "$TTY" ]; then
    printf '%s [%s]: ' "$prompt" "$def" > "$TTY"
    IFS= read -r ans < "$TTY" || ans=""
  fi
  echo "${ans:-$def}"
}

[ -z "$SCOPE" ] && SCOPE=$(ask "Scope (project/user/system)" "user")
case "$SCOPE" in
  project) SETTINGS="$PWD/.claude/settings.json" ;;
  user)    SETTINGS="$HOME/.claude/settings.json" ;;
  system)  SETTINGS="/etc/claude-code/managed-settings.json" ;;
  *) die "invalid scope: $SCOPE (expected project|user|system)" ;;
esac
for v in CACHE BAR_LEN RESERVE WIDTH_FALLBACK; do
  case "${!v}" in *[!0-9]*|'') die "--${v,,} must be an integer" ;; esac
done

# ---- Place usagebar.sh + shared compose.sh ----------------------------------
mkdir -p "$USAGE_DIR" "$BAR_DIR"
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
place() { # src_name dst
  if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/$1" ]; then cp "$SELF_DIR/$1" "$2"
  else curl -fsSL "$REPO_RAW/$1" -o "$2"; fi
  chmod +x "$2"
}
place usagebar.sh "$USAGE_DST"
place compose.sh  "$COMPOSE_DST"

RIGHT_CMD="USAGEBAR_CACHE=$CACHE USAGEBAR_BAR_LEN=$BAR_LEN bash '$USAGE_DST'"
COMPOSE_CMD="bash '$COMPOSE_DST'"

# ---- Determine the LEFT (context) command -----------------------------------
# Priority: existing registry left_cmd -> a contextbar statusLine in the target
# scope -> a contextbar statusLine at user scope -> empty.
LEFT_CMD=""
[ -f "$REG" ] && LEFT_CMD=$(jq -r '.left_cmd // ""' "$REG" 2>/dev/null)
sniff_ctx() { # settings_file -> echo command if it points at contextbar (not compose)
  local f="$1" c
  [ -f "$f" ] || return 0
  c=$(jq -r '.statusLine.command // ""' "$f" 2>/dev/null)
  case "$c" in
    *compose.sh*) return 0 ;;
    *contextbar/statusline.sh*) echo "$c" ;;
  esac
}
if [ -z "$LEFT_CMD" ]; then
  LEFT_CMD=$(sniff_ctx "$SETTINGS")
  [ -z "$LEFT_CMD" ] && LEFT_CMD=$(sniff_ctx "$HOME/.claude/settings.json")
fi
# Last resort: ContextBar script present but not yet wired anywhere.
if [ -z "$LEFT_CMD" ] && [ -f "$CTX_SCRIPT" ]; then
  LEFT_CMD="bash '$CTX_SCRIPT'"
fi

# ---- Write the shared registry ----------------------------------------------
EXIST="{}"; [ -f "$REG" ] && EXIST=$(cat "$REG")
echo "$EXIST" | jq \
  --arg left  "$LEFT_CMD" \
  --arg right "$RIGHT_CMD" \
  --argjson reserve "$RESERVE" \
  --argjson wf "$WIDTH_FALLBACK" \
  '. + {left_cmd: (if $left=="" then (.left_cmd // "") else $left end),
        right_cmd: $right, reserve: $reserve, width_fallback: $wf}' > "$REG.tmp"
mv "$REG.tmp" "$REG"

# ---- Point the chosen settings.json at the composer -------------------------
SUDO=""
if [ "$SCOPE" = "system" ] && [ ! -w "$(dirname "$SETTINGS")" ]; then SUDO="sudo"; fi
$SUDO mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' | $SUDO tee "$SETTINGS" >/dev/null
TMP="$(mktemp)"
$SUDO cat "$SETTINGS" | jq --arg cmd "$COMPOSE_CMD" \
  '.statusLine = {type:"command", command:$cmd, refreshInterval:5}' > "$TMP"
$SUDO cp "$TMP" "$SETTINGS"; rm -f "$TMP"

echo "✓ UsageBar installed"
echo "  usage script: $USAGE_DST"
echo "  composer:     $COMPOSE_DST"
echo "  registry:     $REG"
echo "  settings:     $SETTINGS  (scope: $SCOPE)"
echo "  left (ctx):   ${LEFT_CMD:-<none>}"
echo "  cache: ${CACHE}s  bar-len: $BAR_LEN  reserve: $RESERVE  width-fallback: $WIDTH_FALLBACK"
echo "  Restart Claude Code (or wait for refresh) to see the bars."
