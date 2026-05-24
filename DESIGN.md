# UsageBar — design

## Goal

A second status-line bar showing Claude usage limits (5h session, 7d all-models, 7d Sonnet)
with per-window reset countdowns, sharing the single Claude Code status line with ContextBar
such that **context is always left and usage always right, independent of install order**.

## Output

```
5h <bar> <util>% <reset>   7d <bar> <util>% <reset>   S <bar> <util>% <reset>
```

- Meters: `five_hour`, `seven_day`, `seven_day_sonnet`. Sonnet shown only when non-null.
- `util` rounded int; bar length configurable (default 8); colored green/yellow/red at
  50/80 thresholds.
- `<reset>` = `resets_at - now` compacted to `Xd`/`Xh`/`Xm`.

## Data source

`GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` (from
`~/.claude/.credentials.json`) and `anthropic-beta: oauth-2025-04-20`. Response shape:

```json
{ "five_hour":        {"utilization": 6.0,  "resets_at": "..."},
  "seven_day":        {"utilization": 38.0, "resets_at": "..."},
  "seven_day_sonnet": {"utilization": 5.0,  "resets_at": "..."},
  "seven_day_opus":   null }
```

Cached to `~/.claude/usagebar/cache.json`, TTL 60s. Refresh runs in the background (3s curl
timeout); the status line renders from cache and never blocks. Attempts throttled to once per
TTL via `~/.claude/usagebar/.attempt`, even on failure. Stale-on-failure, empty-on-no-data.

## Components

- **usagebar.sh** — drains stdin, refreshes cache if stale (background), renders the right-hand
  meter string. No alignment logic of its own.
- **compose.sh** (shared, `~/.claude/statusbar/compose.sh`) — runs the registry's `left_cmd`
  and `right_cmd` against the same status-line JSON, strips ANSI to measure visible width, and
  emits `left + gap + right`. Width via `tput cols </dev/tty` → `$COLUMNS` → `width_fallback`.
  `reserve` columns kept clear at the right edge.
- **install.sh** — installs both scripts, writes its slot in the registry, migrates an existing
  ContextBar `statusLine` into `left_cmd`, points the chosen scope's `settings.json` at the
  composer.

## Order-independence mechanism

Single registry `~/.claude/statusbar/parts.json`:

```json
{ "left_cmd": "<context command>", "right_cmd": "<usage command>",
  "reserve": 0, "width_fallback": 120 }
```

`settings.json.statusLine` always points at `compose.sh`. Each bar's installer writes only its
own slot:

- UsageBar installer sets `right_cmd`, and adopts any existing ContextBar command as `left_cmd`.
- ContextBar installer (updated) sets `left_cmd`; if `compose.sh` exists it points `statusLine`
  at the composer, otherwise it runs standalone but still records `left_cmd` so a later UsageBar
  install composes correctly.

Result: whichever is installed second wires up composition; neither clobbers the other.

## Known limitations

- Right-alignment is best-effort. Wide block/dingbat glyphs are counted as one column each, so
  the right edge can drift ±1-2 columns depending on the terminal/font.
- Requires a Claude subscription whose account returns usage windows from the endpoint.

## Decisions

- **Separate repo** from ContextBar (per request), cooperating via the shared composer.
- **60s cache**, background refresh — balances freshness against API call volume given the 5s
  status-line refresh.
- **Sonnet meter conditional** on `seven_day_sonnet` being non-null; opus omitted.
- **Per-window reset countdown** appended to each meter (not a single trailing clock).
