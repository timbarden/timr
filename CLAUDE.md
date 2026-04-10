## Overview

Timr is a macOS time-tracking system delivered as two bash scripts: `timr_install.sh` and `timr_uninstall.sh`. There is no build step, no test suite, and no source tree — the installer is the product. It writes all runtime artifacts (scripts, LaunchAgents, logs, xbar plugin) into the user's `~/Library` on install.

## Architecture

The installer generates and deploys several independent pieces that together form the running system. When editing behavior, identify which piece owns the logic before changing it:

1. **`~/Library/Scripts/timr/timr-start.sh`** — appends a LOGIN line to `sessions.log` and writes the login timestamp to `/tmp/timr-last.txt` **only if the marker doesn't already exist**, so a wake-after-login doesn't clobber the original session start. Runs on login and on wake.
2. **`~/Library/Scripts/timr/timr-stop.sh`** — reads `/tmp/timr-last.txt`, computes session duration, appends LOGOUT to `sessions.log`, and accumulates the day's total into `developer.log` (one line per date: `YYYY-MM-DD <seconds>`). Runs on sleep, on logout, and on shutdown.
3. **`~/Library/Scripts/timr/timr-shutdown-watch.sh`** — a persistent bash wrapper that traps `SIGTERM`/`SIGINT` and calls `timr-stop.sh`. Uses the `sleep & wait` pattern because bash does not process signals while a foreground builtin is blocking. Exists solely so logout/shutdown (which sleepwatcher does **not** cover) closes the in-flight session before the system goes down.
4. **Three LaunchAgents in `~/Library/LaunchAgents/`**:
   - `com.timr.login.plist` — runs `timr-start.sh` at load (boot/login/wake).
   - `com.timr.sleepwatcher.plist` — invokes Homebrew's `sleepwatcher` with `-s timr-stop.sh` (sleep) and `-w timr-start.sh` (wake). sleepwatcher does **not** fire its `-s` script on its own termination, so there's no double-stop conflict with the shutdown watcher.
   - `com.timr.shutdown.plist` — runs `timr-shutdown-watch.sh` with `RunAtLoad` + `KeepAlive`. launchd sends SIGTERM to all agents on logout/shutdown; this one's trap catches it and records the stop.
5. **`~/Library/Application Support/xbar/plugins/timr.30s.sh`** — xbar plugin refreshed every 30s. Reads `developer.log`, adds the in-flight session from `/tmp/timr-last.txt`, computes day/week remaining against `HOURS=35` / `DAYS=5` targets, and emits xbar menu output. Week is determined by `date +%W` (Monday-based week number).

### Event coverage

| Event              | Triggered by              | Runs             |
|--------------------|---------------------------|------------------|
| Boot / login       | `com.timr.login` RunAtLoad | `timr-start.sh` |
| Wake               | sleepwatcher `-w`          | `timr-start.sh` |
| Sleep              | sleepwatcher `-s`          | `timr-stop.sh`  |
| Logout / shutdown  | SIGTERM to shutdown agent  | `timr-stop.sh`  |

Hard power-off / kernel panic cannot be caught. `/tmp/timr-last.txt` is cleared by macOS on next boot, so the in-flight session is simply lost (no stale marker corrupts future sessions).

### Data flow

Events → start/stop scripts → `~/Library/Logs/timr/{sessions.log, developer.log}` + `/tmp/timr-last.txt` (in-flight marker) → xbar plugin reads all three to render the menu bar.

`developer.log` is the source of truth for aggregated time; `sessions.log` is an append-only audit trail; `/tmp/timr-last.txt` signals an active session.

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
