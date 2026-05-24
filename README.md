# UsageBar

Claude **usage-limit meters** for the [Claude Code](https://claude.com/claude-code) status line —
see your 5-hour session, weekly, and Sonnet-weekly quota at a glance, with reset countdowns.

```
5h ▊▊░░░░░░ 6% 2h   7d ▊▊▊░░░░░ 38% 5d   S ▊░░░░░░░ 5% 5d
```

| meter | source | meaning |
|-------|--------|---------|
| `5h` | `five_hour` | current rolling session window |
| `7d` | `seven_day` | weekly limit, all models |
| `S` | `seven_day_sonnet` | weekly limit, Sonnet only — shown **only when present** |

Each meter is `<label> <bar> <util>% <reset>`, where `<reset>` is the compact time left
until that window resets (`Xd` / `Xh` / `Xm`). Bars are colored by utilization
(green `<50%`, yellow `<80%`, red `≥80%`).

## Shares one line with [ContextBar](https://github.com/VocanicZ/ContextBar)

Claude Code has a single status line. UsageBar and ContextBar cooperate through a tiny
composer (`~/.claude/statusbar/compose.sh` + registry `~/.claude/statusbar/parts.json`):

```
<context bar ......... left>                          5h ▊▊ 6% 2h   7d ▊▊▊ 38% 5d
```

- **Context is always on the left, usage always on the right** — regardless of which you
  install first. Each installer writes only its own slot in the registry.
- Right-alignment is **best-effort**: the status-line process isn't a TTY and Claude Code
  doesn't pass the width, so width is probed via `tput cols </dev/tty` → `$COLUMNS` →
  `--width-fallback`. Wide glyphs can drift the edge by a column or two.
- `--reserve N` keeps `N` columns clear at the far right for Claude Code's own indicators.

UsageBar works on its own too (right-aligned, empty left) if ContextBar isn't installed.

## Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/VocanicZ/UsageBar/main/install.sh | bash
```

Skip the prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/VocanicZ/UsageBar/main/install.sh \
  | bash -s -- --scope user --cache 60 --bar-len 8 --reserve 0
```

### Installer flags

| flag | default | meaning |
|------|---------|---------|
| `--scope` | (prompt) | `project` `user` `system` — which `settings.json` to write |
| `--cache` | `60` | usage cache TTL, seconds |
| `--bar-len` | `8` | meter length in glyphs |
| `--reserve` | `0` | columns kept clear at far right for Claude's own status |
| `--width-fallback` | `120` | terminal width assumed when it can't be probed |

### Scope → file

| scope | file |
|-------|------|
| `project` | `./.claude/settings.json` |
| `user` | `~/.claude/settings.json` |
| `system` | `/etc/claude-code/managed-settings.json` (needs `sudo`) |

## How usage data is fetched

UsageBar reads your oauth token from `~/.claude/.credentials.json` and calls
`GET https://api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`)
— the same endpoint Claude Code's `/usage` view uses. Responses are cached to
`~/.claude/usagebar/cache.json`; the call runs in the **background** with a 3s timeout and
never blocks the status line. On network/token failure the last cached value is shown.

This is a read-only request against **your own** account. The token never leaves your machine
except in that request to Anthropic.

## Runtime configuration

`usagebar.sh` honors these environment variables (set on the registry's `right_cmd`):

| env var | default | meaning |
|---------|---------|---------|
| `USAGEBAR_CACHE` | `60` | cache TTL seconds |
| `USAGEBAR_BAR_LEN` | `8` | bar length |
| `USAGEBAR_FILLED` | `▊` | filled glyph |
| `USAGEBAR_EMPTY` | `░` | empty glyph |
| `USAGEBAR_NO_COLOR` | (unset) | disable threshold coloring |
| `USAGEBAR_SEP` | 3 spaces | separator between meters |

## Requirements

- `bash`, `jq`, `curl`, `awk`, `date` (GNU)
- A Claude subscription with usage limits (Pro/Max); the endpoint returns your windows.

## Uninstall

Remove `"statusLine"` from the relevant `settings.json` (or restore the ContextBar command),
delete `~/.claude/usagebar/`, and remove the `right_cmd` from `~/.claude/statusbar/parts.json`.

## License

MIT
