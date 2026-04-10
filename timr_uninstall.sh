#!/bin/bash
# Timr uninstaller for macOS

# add 'are you sure' prompt
read -p "Uninstalling Timr will remove all associated logs and files. Are you sure? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# Unload agents using the modern bootout API (legacy `unload` still works
# but prints deprecation warnings on Sonoma+). Errors are suppressed
# because agents may not be loaded.
GUI_DOMAIN="gui/$(id -u)"
launchctl bootout "$GUI_DOMAIN/com.timr.login" 2>/dev/null
launchctl bootout "$GUI_DOMAIN/com.timr.sleepwatcher" 2>/dev/null
launchctl bootout "$GUI_DOMAIN/com.timr.shutdown" 2>/dev/null

# Remove all timr files
rm -f ~/Library/Application\ Support/xbar/plugins/timr.30s.sh
rm -f ~/Library/Application\ Support/xbar/plugins/timr.30s.sh.vars.json
rm -rf ~/Library/Application\ Support/timr
rm -f ~/Library/LaunchAgents/com.timr.login.plist
rm -f ~/Library/LaunchAgents/com.timr.sleepwatcher.plist
rm -f ~/Library/LaunchAgents/com.timr.shutdown.plist
rm -rf ~/Library/Logs/timr
rm -rf ~/Library/Scripts/timr
rm -f /tmp/timr-last.txt

# Refresh xbar (quit if running, then relaunch — use `;` so relaunch still
# happens when xbar isn't running)
osascript -e 'tell application "xbar" to quit' 2>/dev/null; open -a xbar 2>/dev/null

echo "Timr uninstalled."
