# Timr - Time Tracking System

A lightweight time-tracking system for macOS that automatically logs work hours and displays progress in the menu bar.

## Screenshots

<img src="screenshot-1.png" alt="Timr Menu Bar Screenshot" width="300">

*Timr showing daily and weekly progress in the menu bar*

<img src="screenshot-2.png" alt="Timr Menu Bar Screenshot" width="300">

*Timr showing one fifth of hours completed*

## Dependencies

Timr requires these dependencies that will request installation during setup:
- **xbar** - For menu bar display
- **sleepwatcher** - For sleep/wake tracking

## Installation

Run the install script - it will check for any missing dependencies:

```bash
./timr_install.sh
```

The installer will:
1. Check for required dependencies (xbar, sleepwatcher)
2. Offer to install them automatically via Homebrew if missing
3. Install the xbar menu bar plugin

After installation, log in (or sleep/wake) to start tracking time.

## What it does

- Automatically tracks time across login, wake, sleep, logout, and shutdown
- Shows progress in your menu bar with visual indicators
- Targets: 7 hours per day, 35 hours per week
- Click the menu bar item to access your time logs

### How sessions are captured

| Event              | How it's captured                                    |
|--------------------|------------------------------------------------------|
| Boot / login       | Login LaunchAgent runs the start script at load     |
| Wake               | `sleepwatcher -w` runs the start script             |
| Sleep              | `sleepwatcher -s` runs the stop script              |
| Logout / shutdown  | Persistent agent traps SIGTERM and runs the stop script |

Hard power-off and kernel panics cannot be caught — in those cases the in-flight session is lost, but future sessions recover cleanly on next boot.

## Uninstall

```bash
./timr_uninstall.sh
```