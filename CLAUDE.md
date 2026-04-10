## Overview

Timr is a macOS time-tracking system delivered as two bash scripts: `timr_install.sh` and `timr_uninstall.sh`. There is no build step, no test suite, and no source tree — the installer is the product. It writes all runtime artifacts (scripts, LaunchAgents, logs, xbar plugin) into the user's `~/Library` on install.

## Architecture

The installer generates and deploys four independent pieces that together form the running system. When editing behavior, identify which piece owns the logic before changing it:

1. **`~/Library/Scripts/timr/timr-start.sh`** — writes login timestamp to `/tmp/timr-last.txt` and appends a LOGIN line to `sessions.log`. Runs on login and on wake.
2. **`~/Library/Scripts/timr/timr-stop.sh`** — reads `/tmp/timr-last.txt`, computes session duration, appends LOGOUT to `sessions.log`, and accumulates the day's total into `developer.log` (one line per date: `YYYY-MM-DD <seconds>`). Runs on sleep.
3. **`~/Library/LaunchAgents/com.timr.login.plist`** and **`com.timr.sleepwatcher.plist`** — the login agent runs `timr-start.sh` at load; the sleepwatcher agent invokes Homebrew's `sleepwatcher` binary with `-s` (stop on sleep) and `-w` (start on wake).
4. **`~/Library/Application Support/xbar/plugins/timr.30s.sh`** — xbar plugin refreshed every 30s. Reads `developer.log`, adds the in-flight session from `/tmp/timr-last.txt`, computes day/week remaining against `HOURS=35` / `DAYS=5` targets, and emits xbar menu output. Week is determined by `date +%W` (ISO week, Monday start).

### Data flow

`sleepwatcher` / login → start/stop scripts → `~/Library/Logs/timr/{sessions.log, developer.log}` + `/tmp/timr-last.txt` (in-flight marker) → xbar plugin reads all three to render the menu bar.

`developer.log` is the source of truth for aggregated time; `sessions.log` is an append-only audit trail; `/tmp/timr-last.txt` signals an active session.

### Editing generated scripts

All four deployed files are heredocs inside `timr_install.sh`. To change runtime behavior, edit the heredoc body in the installer — **not** the installed file, which will be overwritten on the next install. The heredocs use `<< 'EOF'` (quoted), so `$VAR` inside them is expanded at script runtime, not install time. The exceptions are the plist `ProgramArguments` which use `$(whoami)` — this is expanded by `launchctl`/shell at agent load, so the installed plist contains a literal `$(whoami)`.

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
