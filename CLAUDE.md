## Overview

Timr is a macOS time-tracking system delivered as two bash scripts: `timr_install.sh` and `timr_uninstall.sh`. There is no build step, no test suite, and no source tree — the installer is the product. It writes all runtime artifacts (scripts, LaunchAgents, logs, xbar plugin) into the user's `~/Library` on install.

## Architecture

The installer generates and deploys several independent pieces that together form the running system. When editing behavior, identify which piece owns the logic before changing it:

1. **`~/Library/Scripts/timr/timr-start.sh`** — takes an optional *reason* argument (`login`, `wake`, `resume`, etc., defaults to `unknown`), appends a `START <reason>` line to `sessions.log`, and writes the timestamp to `/tmp/timr-last.txt` **only if the marker doesn't already exist**. Before doing either, it checks for the pause flag (see below) and exits early if the timer is paused — this is what prevents a lid-close/wake cycle from silently undoing a manual pause.
2. **`~/Library/Scripts/timr/timr-stop.sh`** — takes an optional reason argument, reads `/tmp/timr-last.txt`, computes session duration, appends `STOP <reason> (Session: N seconds)` to `sessions.log`, and accumulates the day's total into `developer.log` (one line per date: `YYYY-MM-DD <seconds>`). Only accumulates when duration is non-zero, so a redundant stop (e.g. shutdown trap firing while already paused) doesn't add a zero-duration entry.
3. **`~/Library/Scripts/timr/timr-shutdown-watch.sh`** — a persistent bash wrapper that traps `SIGTERM`/`SIGINT` and calls `timr-stop.sh shutdown`. Uses the `sleep & wait` pattern because bash does not process signals while a foreground builtin is blocking. Exists solely so logout/shutdown (which sleepwatcher does **not** cover) closes the in-flight session before the system goes down.
4. **Three LaunchAgents in `~/Library/LaunchAgents/`**:
   - `com.timr.login.plist` — runs `timr-start.sh login` at load (boot/login).
   - `com.timr.sleepwatcher.plist` — invokes Homebrew's `sleepwatcher` with `-s "timr-stop.sh sleep"` and `-w "timr-start.sh wake"`. sleepwatcher passes these strings through `/bin/sh`, so space-separated args work. sleepwatcher does **not** fire its `-s` script on its own termination, so there's no double-stop conflict with the shutdown watcher.
   - `com.timr.shutdown.plist` — runs `timr-shutdown-watch.sh` with `RunAtLoad` + `KeepAlive`. launchd sends SIGTERM to all agents on logout/shutdown; this one's trap catches it and records the stop.
5. **`~/Library/Application Support/xbar/plugins/timr.30s.sh`** — xbar plugin refreshed every 30s. Reads `developer.log`, adds the in-flight session from `/tmp/timr-last.txt`, computes day/week remaining against `HOURS` / `DAYS` targets from the Timr config file, and emits xbar menu output. Also owns all in-menu settings (hour/day presets, pause/resume) via xbar action handlers — the plugin re-invokes itself with `$1` set to an action name, handles the action, and `exit 0`s before rendering. Week is determined by `date +%W` (Monday-based week number).

### Event coverage

| Event              | Triggered by              | Runs                      |
|--------------------|---------------------------|---------------------------|
| Boot / login       | `com.timr.login` RunAtLoad | `timr-start.sh login`    |
| Wake               | sleepwatcher `-w`          | `timr-start.sh wake`     |
| Sleep              | sleepwatcher `-s`          | `timr-stop.sh sleep`     |
| Logout / shutdown  | SIGTERM to shutdown agent  | `timr-stop.sh shutdown`  |
| Manual pause       | xbar menu → Pause          | `timr-stop.sh pause` + touch pause flag |
| Manual resume      | xbar menu → Resume         | rm pause flag + `timr-start.sh resume`  |

Hard power-off / kernel panic cannot be caught. `/tmp/timr-last.txt` is cleared by macOS on next boot, so the in-flight session is simply lost (no stale marker corrupts future sessions).

### State files

Everything Timr mutates at runtime lives in one of two places:

- `/tmp/timr-last.txt` — in-flight marker. Presence means a session is open; its contents are the session start timestamp. Cleared by macOS on reboot.
- `~/Library/Application Support/timr/` — persistent state and config, owned by the xbar plugin:
  - `config` — `HOURS=<n>` / `DAYS=<n>` KEY=VALUE lines, written by the Settings action handlers. Read defensively (no `source`) on each plugin refresh, which is why in-menu config changes take effect instantly. **Do not reintroduce xbar's `vars.json` system here** — xbar caches it in memory and only re-reads it when its own preferences UI writes, which breaks the dropdown-settings flow.
  - `paused` — pause flag. Presence means manual pause is active. Its mtime is the moment pause was activated (used to compute paused duration for the resume prompt).
  - `last-prompt` — rate-limit marker. Its mtime is the last time the resume prompt was shown; the plugin won't re-prompt within 5 minutes of it.

### Pause semantics

Manual pause is implemented as *stop + flag*: it runs the normal stop script (so the current session's seconds are committed to `developer.log` immediately — a crash during pause loses nothing) and then touches the pause flag. Resume is *remove flag + start*. The subtlety is that `timr-start.sh` must honour the pause flag on every invocation, because sleepwatcher's `-w` will otherwise fire on wake and re-open the session. The flag is the single source of truth for "is manual pause active"; the xbar plugin reads it on every refresh.

### Resume prompt

On each 30s refresh, if the pause flag exists AND it's been set for more than 60 seconds AND `ioreg -c IOHIDSystem` reports a `HIDIdleTime` under 10 seconds AND `last-prompt` is older than 5 minutes, the plugin shows a blocking `osascript` dialog asking whether to resume. Clicking Resume calls `do_resume` inline and lets the render continue, so the new state shows in the same refresh. The rate limit prevents spam if the user dismisses the dialog and keeps working.

### Data flow

Events → start/stop scripts → `~/Library/Logs/timr/{sessions.log, developer.log}` + `/tmp/timr-last.txt` (in-flight marker) + `~/Library/Application Support/timr/paused` (pause flag) → xbar plugin reads all four to render the menu bar.

`developer.log` is the source of truth for aggregated time; `sessions.log` is an append-only audit trail using the format `<timestamp> START|STOP <reason> <user> [(Session: N seconds)]`; `/tmp/timr-last.txt` signals an active session; the pause flag signals manual pause.

### Editing generated scripts

All deployed files are heredocs inside `timr_install.sh`. To change runtime behavior, edit the heredoc body in the installer — **not** the installed file, which will be overwritten on the next install. Two heredoc styles are used deliberately:

- **Shell scripts** use `<< 'EOF'` (quoted) so `$VAR` is expanded at script runtime, not install time.
- **Plists** use `<< EOF` (unquoted) so `$HOME` and `$SLEEPWATCHER_BIN` are expanded at install time and baked into the plist. launchd does **not** expand `$VAR` or `$(...)` inside `ProgramArguments`, so paths must be fully resolved before being written. An earlier bug where the plists contained a literal `/Users/$(whoami)/...` silently broke the login agent for a long time — don't reintroduce it.

## Common commands

```bash
./timr_install.sh      # install or reinstall (unloads existing agents first)
./timr_uninstall.sh    # removes agents, scripts, logs, and xbar plugin
```

To test a change end-to-end: run the installer, then sleep/wake the Mac (or manually run `~/Library/Scripts/timr/timr-start.sh` and `timr-stop.sh`) and check `~/Library/Logs/timr/`. The xbar plugin can be run directly: `~/Library/Application\ Support/xbar/plugins/timr.30s.sh`.

## Blocked commands

**NEVER run these commands - they can destroy uncommitted work:**

- `git restore` - Discards uncommitted changes permanently
- `git checkout -- <file>` - Same as restore, discards changes
- `git reset --hard` - Destroys all uncommitted work
- `git clean -f` - Deletes untracked files permanently

## Dependencies

Runtime: `sleepwatcher` (Homebrew) and `xbar` (Homebrew cask). The installer checks for both at standard Homebrew paths (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel) and offers to install them.
