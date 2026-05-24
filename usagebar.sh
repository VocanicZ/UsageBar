#!/usr/bin/env bash
# UsageBar — Claude usage-limit meters for the Claude Code status line.
#
# Renders:  5h <bar> <util>% <reset>   7d <bar> <util>% <reset>   S <bar> <util>% <reset>
#   5h  five_hour      (current session window)
#   7d  seven_day      (weekly, all models)
#   S   seven_day_sonnet (weekly, Sonnet only — shown only when present)
#   <reset> = compact time left until that window resets (Xd / Xh / Xm)
#
# Data: GET https://api.anthropic.com/api/oauth/usage using the oauth token in
# ~/.claude/.credentials.json. Cached to ~/.claude/usagebar/cache.json; the network
# call runs in the background and never blocks the status line.
#
# Config (environment):
#   USAGEBAR_CACHE     cache TTL seconds (default 60)
#   USAGEBAR_BAR_LEN   bar length in glyphs (default 8)
#   USAGEBAR_FILLED    filled glyph (default ▊)
#   USAGEBAR_EMPTY     empty glyph  (default ░)
#   USAGEBAR_NO_COLOR  set to disable threshold coloring
#   USAGEBAR_SEP       separator between meters (default 3 spaces)

CACHE_DIR="$HOME/.claude/usagebar"
CACHE="$CACHE_DIR/cache.json"
ATTEMPT="$CACHE_DIR/.attempt"
CREDS="$HOME/.claude/.credentials.json"
URL="https://api.anthropic.com/api/oauth/usage"
BETA="oauth-2025-04-20"

TTL=${USAGEBAR_CACHE:-60}
LEN=${USAGEBAR_BAR_LEN:-8}
FILLED=${USAGEBAR_FILLED:-▊}
EMPTY=${USAGEBAR_EMPTY:-░}
SEP=${USAGEBAR_SEP:-"   "}

R=$'\033[0m'
DIM=$'\033[2m'

# Drain stdin (composer feeds the same status-line JSON to every part).
_=$(cat 2>/dev/null)

mkdir -p "$CACHE_DIR" 2>/dev/null
now=$(date +%s)

fetch() {
  local tok
  tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null)
  [ -z "$tok" ] && return 1
  curl -fsS --max-time 3 "$URL" \
    -H "Authorization: Bearer $tok" \
    -H "anthropic-beta: $BETA" \
    -o "$CACHE.tmp" 2>/dev/null \
    && mv "$CACHE.tmp" "$CACHE" 2>/dev/null
}

# Decide whether to refresh. Throttle attempts to once per TTL even on failure.
fresh=0
if [ -f "$CACHE" ]; then
  mtime=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  [ $(( now - mtime )) -lt "$TTL" ] && fresh=1
fi
if [ "$fresh" -ne 1 ]; then
  amtime=$(stat -c %Y "$ATTEMPT" 2>/dev/null || echo 0)
  if [ $(( now - amtime )) -ge "$TTL" ]; then
    touch "$ATTEMPT" 2>/dev/null
    if [ -f "$CACHE" ]; then
      ( fetch ) >/dev/null 2>&1 &      # have stale data: refresh in background
    else
      fetch                            # cold start: one bounded sync fetch
    fi
  fi
fi

[ -f "$CACHE" ] || exit 0
data=$(cat "$CACHE" 2>/dev/null)
[ -z "$data" ] && exit 0

countdown() { # resets_at -> "Xd"/"Xh"/"Xm"  (empty if unknown)
  local reset="$1" te d
  [ "$reset" = "null" ] || [ -z "$reset" ] && return 0
  te=$(date -d "$reset" +%s 2>/dev/null) || return 0
  [ -z "$te" ] && return 0
  d=$(( te - now )); [ $d -lt 0 ] && d=0
  if   [ $d -ge 86400 ]; then echo "$(( d/86400 ))d"
  elif [ $d -ge 3600  ]; then echo "$(( d/3600 ))h"
  else echo "$(( (d+59)/60 ))m"; fi
}

meter() { # label utilization resets_at
  local label="$1" util="$2" reset="$3"
  { [ "$util" = "null" ] || [ -z "$util" ]; } && return 0
  local u f bar="" i=0 c="" cd
  u=$(awk -v v="$util" 'BEGIN{printf "%.0f", v}')
  f=$(awk -v u="$u" -v L="$LEN" 'BEGIN{x=u*L/100; printf "%.0f", x}')
  [ "$f" -gt "$LEN" ] && f=$LEN; [ "$f" -lt 0 ] && f=0
  while [ $i -lt $f ];   do bar+="$FILLED"; i=$((i+1)); done
  while [ $i -lt $LEN ]; do bar+="$EMPTY";  i=$((i+1)); done
  if [ -z "${USAGEBAR_NO_COLOR:-}" ]; then
    if   [ "$u" -ge 80 ]; then c=$'\033[38;2;220;80;80m'
    elif [ "$u" -ge 50 ]; then c=$'\033[38;2;255;193;7m'
    else c=$'\033[38;2;80;200;120m'; fi
  fi
  cd=$(countdown "$reset")
  printf '%s %s%s%s %d%%%s' "$label" "$c" "$bar" "$R" "$u" "${cd:+ $DIM$cd$R}"
}

fh_u=$(jq -r '.five_hour.utilization // "null"'        <<<"$data")
fh_r=$(jq -r '.five_hour.resets_at // "null"'          <<<"$data")
sd_u=$(jq -r '.seven_day.utilization // "null"'        <<<"$data")
sd_r=$(jq -r '.seven_day.resets_at // "null"'          <<<"$data")
ss_u=$(jq -r '.seven_day_sonnet.utilization // "null"' <<<"$data")
ss_r=$(jq -r '.seven_day_sonnet.resets_at // "null"'   <<<"$data")

out=""
add() { [ -z "$1" ] && return; [ -n "$out" ] && out+="$SEP"; out+="$1"; }
add "$(meter 5h "$fh_u" "$fh_r")"
add "$(meter 7d "$sd_u" "$sd_r")"
add "$(meter S  "$ss_u" "$ss_r")"

printf '%s' "$out"
