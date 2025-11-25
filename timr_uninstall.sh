# add 'are you sure' prompt
read -p "Uninstalling Timr will remove all associated logs and files. Are you sure? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# remove all timr files
launchctl unload ~/Library/LaunchAgents/com.timr.login.plist
launchctl unload ~/Library/LaunchAgents/com.timr.sleepwatcher.plist
 
rm -f ~/Library/Application\ Support/xbar/plugins/timr.30s.sh
rm -f ~/Library/LaunchAgents/com.timr.login.plist
rm -f ~/Library/LaunchAgents/com.timr.sleepwatcher.plist
rm -rf ~/Library/Logs/timr
rm -rf ~/Library/Scripts/timr

# refresh xbar
osascript -e 'tell application "xbar" to quit' && open -a xbar

echo "Timr uninstalled."