# Timr - Time Tracking System

A lightweight time-tracking system for macOS that automatically logs work hours and displays progress in the menu bar.

<div style="color: gray;">
    <figure style="margin: 2em 0;">
    <img src="screenshot-1.png" alt="Timr Menu Bar Screenshot" style="max-width: 250px;" />
    <figcaption>Timr showing daily and weekly progress in the menu bar</figcaption>
    </figure>
    <figure style="margin: 2em 0; color: gray;">
    <img src="screenshot-2.png" alt="Timr Time Log Screenshot" style="max-width: 250px;" />
    <figcaption>Timr showing one fifth of hours completed</figcaption>
    </figure>
</div>

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

After installation, sleep and wake the Mac to start tracking time

## What it does

- Automatically tracks time when you sleep or log in/out
- Shows progress in your menu bar with visual indicators
- Targets: 7 hours per day, 35 hours per week
- Click the menu bar item to access your time logs

## Uninstall

```bash
./timr_uninstall.sh
```