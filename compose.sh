#!/usr/bin/env bash
# statusbar composer — renders a LEFT part (context) and a RIGHT part (usage) on
# one status line, right-aligning the RIGHT part.
#
# Shared by ContextBar and UsageBar. Installed to ~/.claude/statusbar/compose.sh.
# Reads a registry at ~/.claude/statusbar/parts.json:
#   { "left_cmd": "...", "right_cmd": "...", "reserve": 0, "width_fallback": 120 }
# Either bar's installer writes only its own slot, so install order does not matter:
# context is always LEFT, usage is always RIGHT.
#
# Terminal width: the status-line subprocess has no controlling TTY and Claude Code
# does not pass the width on stdin, so we walk the parent process tree to find the
# `claude` process's pts and read its winsize (`stty size`). Falls back to
# `tput cols`, $COLUMNS, then width_fallback for non-Linux / no-/proc systems.
# `reserve` columns are kept clear at the far right for Claude Code's own indicators
# (e.g. `● high · /effort`), so the RIGHT part sits just to their left.

INPUT=$(cat)
REG="${STATUSBAR_PARTS:-$HOME/.claude/statusbar/parts.json}"

left_cmd=""; right_cmd=""; reserve=0; width_fallback=120
if [ -f "$REG" ]; then
  left_cmd=$(jq -r  '.left_cmd // ""'       "$REG" 2>/dev/null)
  right_cmd=$(jq -r '.right_cmd // ""'      "$REG" 2>/dev/null)
  reserve=$(jq -r   '.reserve // 0'         "$REG" 2>/dev/null)
  width_fallback=$(jq -r '.width_fallback // 120' "$REG" 2>/dev/null)
fi
case "$reserve"        in ''|*[!0-9]*) reserve=0 ;; esac
case "$width_fallback" in ''|*[!0-9]*) width_fallback=120 ;; esac

run_part() { # cmd  — feed the status-line JSON on stdin
  [ -z "$1" ] || [ "$1" = "null" ] && return 0
  printf '%s' "$INPUT" | eval "$1" 2>/dev/null
}
LEFT=$(run_part "$left_cmd")
RIGHT=$(run_part "$right_cmd")

# No right part: behave exactly like the left status line alone.
if [ -z "$RIGHT" ]; then
  printf '%s\n' "$LEFT"
  exit 0
fi

strip() { sed $'s/\x1b\\[[0-9;]*m//g'; }
vlen() { local s; s=$(printf '%s' "$1" | strip | tr -d '\n'); printf '%s' "${#s}"; }

# Terminal width — walk parent tree to the controlling pts, read its column count.
probe_tree_width() {
  local p=$$ i fd link sz np
  for i in 1 2 3 4 5 6 7 8; do
    for fd in 0 1 2; do
      link=$(readlink "/proc/$p/fd/$fd" 2>/dev/null) || continue
      case "$link" in
        /dev/pts/*|/dev/tty*)
          sz=$(stty size <"$link" 2>/dev/null) && { printf '%s' "${sz##* }"; return 0; } ;;
      esac
    done
    np=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
    { [ -z "$np" ] || [ "$np" = "0" ]; } && return 1
    p=$np
  done
  return 1
}
width=$(probe_tree_width)
[ -z "$width" ] && width=$(tput cols 2>/dev/null </dev/tty)
[ -z "$width" ] && width=${COLUMNS:-}
case "$width" in ''|*[!0-9]*) width=$width_fallback ;; esac
[ "$width" -lt 20 ] && width=$width_fallback

ll=$(vlen "$LEFT")
rl=$(vlen "$RIGHT")
gap=$(( width - reserve - ll - rl ))
[ "$gap" -lt 1 ] && gap=1
pad=$(printf '%*s' "$gap" '')

printf '%s%s%s\n' "$LEFT" "$pad" "$RIGHT"
