# Timr - Time Tracking System

A lightweight time tracking system for macOS that automatically logs work hours and displays progress in the menu bar.

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
3. Install the menu bar plugin

After installation, restart your Mac or log out

## What it does

- Automatically tracks time when you log in/out
- Shows progress in your menu bar with visual indicators
- Targets: 7 hours per day, 35 hours per week
- Click the menu bar item to access your time logs

## Uninstall

```bash
./timr_uninstall.sh
```