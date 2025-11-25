#!/bin/bash
# Timr installer for macOS


# Function to check and install Homebrew if needed
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        echo "Homebrew not found. Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}


echo "Installing Timr..."


# Check for sleepwatcher requirement
if [ ! -f "/opt/homebrew/opt/sleepwatcher/sbin/sleepwatcher" ] && [ ! -f "/usr/local/opt/sleepwatcher/sbin/sleepwatcher" ]; then
    echo ""
    echo "⚠️  Timr requires sleepwatcher but is not found"
    echo ""
    echo "Would you like to install sleepwatcher automatically? (requires Homebrew)"
    read -p "Install sleepwatcher? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        check_homebrew
        
        echo "Installing sleepwatcher via Homebrew..."
        brew install sleepwatcher

        echo "✅ sleepwatcher installed! Timr installer will continue..."
        echo ""
    else
        echo ""
        echo "Manual installation required:"
        echo "1. Install Homebrew: https://brew.sh/"
        echo "2. Run: brew install sleepwatcher"
        echo "3. Then run this installer again"
        echo ""
        exit 1
    fi
fi

# Check for xbar requirement
if [ ! -d "/Applications/xbar.app" ] && [ ! -d "~/Applications/xbar.app" ]; then
    echo ""
    echo "⚠️  xbar is required but not found!"
    echo ""
    echo "Would you like to install xbar automatically? (requires Homebrew)"
    read -p "Install xbar? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        check_homebrew
        
        echo "Installing xbar via Homebrew..."
        brew install --cask xbar
        
        echo ""
        echo "✅ xbar installed! Timr installer will continue..."
        echo ""
    else
        echo ""
        echo "Manual installation required:"
        echo "1. Visit: https://xbarapp.com/"
        echo "2. Download and install xbar"
        echo "3. Run xbar once to set it up"
        echo "4. Then run this installer again"
        echo ""
        exit 1
    fi
fi


# Create directories
mkdir -p ~/Library/Logs/timr
chmod 755 ~/Library ~/Library/Logs ~/Library/Logs/timr


# Create log files if they don't already exist
if [ ! -f ~/Library/Logs/timr/timr-sessions.txt ]; then
    touch ~/Library/Logs/timr/timr-sessions.txt
fi
if [ ! -f ~/Library/Logs/timr/timr-times.txt ]; then
    touch ~/Library/Logs/timr/timr-times.txt
fi
chmod 600 ~/Library/Logs/timr/*.txt


# Create scripts
mkdir -p ~/Library/Scripts/timr


# Create login script ---
cat << 'EOF' > ~/Library/Scripts/timr/timr-start.sh
#!/bin/bash
USERNAME=$(whoami)
LOGIN_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "$LOGIN_TIME" > /tmp/timr-last.txt
echo "$LOGIN_TIME LOGIN $USERNAME" >> ~/Library/Logs/timr/timr-sessions.txt
EOF
chmod +x ~/Library/Scripts/timr/timr-start.sh


# Create stop script ---
cat << 'EOF' > ~/Library/Scripts/timr/timr-stop.sh
#!/bin/bash
USERNAME=$(whoami)
LOGOUT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
DATE=$(date '+%Y-%m-%d')

if [ -f /tmp/timr-last.txt ]; then
    LOGIN_TIME=$(cat /tmp/timr-last.txt)
    LOGIN_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LOGIN_TIME" "+%s")
    LOGOUT_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LOGOUT_TIME" "+%s")
    DURATION=$((LOGOUT_EPOCH - LOGIN_EPOCH))
else
    DURATION=0
fi

echo "$LOGOUT_TIME LOGOUT $USERNAME (Session: $DURATION seconds)" >> ~/Library/Logs/timr/timr-sessions.txt

if grep -q "^$DATE" ~/Library/Logs/timr/timr-times.txt; then
    OLD_TOTAL=$(grep "^$DATE" ~/Library/Logs/timr/timr-times.txt | awk '{print $2}')
    NEW_TOTAL=$((OLD_TOTAL + DURATION))
    sed -i '' "/^$DATE/c\\
$DATE $NEW_TOTAL
" ~/Library/Logs/timr/timr-times.txt
else
    echo "$DATE $DURATION" >> ~/Library/Logs/timr/timr-times.txt
fi

rm -f /tmp/timr-last.txt
EOF
chmod +x ~/Library/Scripts/timr/timr-stop.sh


# Create LaunchAgents ---
mkdir -p ~/Library/LaunchAgents


# Login agent
cat << 'EOF' > ~/Library/LaunchAgents/com.timr.login.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.timr.login</string>
        <key>ProgramArguments</key>
        <array>
            <string>/Users/$(whoami)/Library/Scripts/timr/timr-start.sh</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
    </dict>
</plist>
EOF

# Create sleepwatcher agent
cat << 'EOF' > ~/Library/LaunchAgents/com.timr.sleepwatcher.plist
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.timr.sleepwatcher</string>
        <key>ProgramArguments</key>
        <array>
            <string>/opt/homebrew/opt/sleepwatcher/sbin/sleepwatcher</string>
            <!-- Verbose mode flag (shows detailed logging of sleepwatcher activity) -->
            <string>-V</string>
            <!-- Sleep flag, followed by the script to run when the system goes to sleep -->
            <string>-s</string>
            <string>/Users/$(whoami)/Library/Scripts/timr/timr-stop.sh</string>
            <!-- Wake flag, followed by the script to run when the system wakes up -->
            <string>-w</string>
            <string>/Users/$(whoami)/Library/Scripts/timr/timr-start.sh</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
    </dict>
</plist>
EOF


# check for existence of agents first
launchctl list | grep com.timr
if [ $? -eq 0 ]; then
    echo "Timr agents already loaded. Unloading existing agents..."
    launchctl unload ~/Library/LaunchAgents/com.timr.login.plist
    launchctl unload ~/Library/LaunchAgents/com.timr.sleepwatcher.plist
fi


# launch agents
launchctl load ~/Library/LaunchAgents/com.timr.login.plist
launchctl load ~/Library/LaunchAgents/com.timr.sleepwatcher.plist


# create xbar plugin
mkdir -p ~/Library/Application\ Support/xbar/plugins
cat << 'EOF' > ~/Library/Application\ Support/xbar/plugins/timr.30s.sh
#!/bin/bash
# Timr xbar plugin
# Shows day and weekly times

LOGGED_TIMES="$HOME/Library/Logs/timr/timr-times.txt"
SESSION_LOGS="$HOME/Library/Logs/timr/timr-sessions.txt"
TEMP_FILE="/tmp/timr-last.txt"
TODAY=$(date "+%Y-%m-%d")

# Today's total
TODAY_SECONDS=0
if grep -q "^$TODAY" "$LOGGED_TIMES" 2>/dev/null; then
    TODAY_SECONDS=$(grep "^$TODAY" "$LOGGED_TIMES" | awk '{print $2}')
fi

# Add current session
if [ -f "$TEMP_FILE" ]; then
    LOGIN_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(cat $TEMP_FILE)" "+%s")
    NOW_EPOCH=$(date "+%s")
    TODAY_SECONDS=$((TODAY_SECONDS + NOW_EPOCH - LOGIN_EPOCH))
fi

# Format HH:MM:SS
h=$((TODAY_SECONDS/3600))
m=$(((TODAY_SECONDS%3600)/60))

# Weekly total
WEEK=$(date +%U)
WEEK_SECONDS=$(awk -v week="$WEEK" '
{
    split($1,d,"-");
    cmd="date -jf %Y-%m-%d " $1 " +%U";
    cmd | getline w; close(cmd);
    if (w == week) total+=$2;
}
END { print total }
' "$LOGGED_TIMES" 2>/dev/null)

[ -z "$WEEK_SECONDS" ] && WEEK_SECONDS=0

# Add current session to week
if [ -f "$TEMP_FILE" ]; then
    WEEK_SECONDS=$((WEEK_SECONDS + NOW_EPOCH - LOGIN_EPOCH))
fi

wh=$((WEEK_SECONDS/3600))
wm=$(((WEEK_SECONDS%3600)/60))

DAYS=5
HOURS=35

# delete the week_fmt from the total hours so it counts down
TOTAL_WEEK_SECONDS=$((HOURS * 3600))
REMAINING_WEEK_SECONDS=$((TOTAL_WEEK_SECONDS - WEEK_SECONDS))
rwh=$((REMAINING_WEEK_SECONDS/3600))
rwm=$(((REMAINING_WEEK_SECONDS%3600)/60))
WEEK_REMAIN=$(printf "%2dh %02dmin" "$rwh" "$rwm")
WEEK_OUTPUT="Week remaining: $WEEK_REMAIN"
if [ $REMAINING_WEEK_SECONDS -lt 0 ]; then
    WEEK_OUTPUT="Week completed! Overtime: $WEEK_REMAIN"
fi

# calculate a day remain value based on TOTAL_WEEK_SECONDS/DAYS
TOTAL_DAY_SECONDS=$((TOTAL_WEEK_SECONDS/DAYS))
REMAINING_DAY_SECONDS=$((TOTAL_DAY_SECONDS - TODAY_SECONDS))
rdh=$((REMAINING_DAY_SECONDS/3600))
rdm=$(((REMAINING_DAY_SECONDS%3600)/60))
DAY_REMAIN=$(printf "%2dh %02dmin" "$rdh" "$rdm")
DAY_OUTPUT="Day remaining: $DAY_REMAIN"
if [ $REMAINING_DAY_SECONDS -lt 0 ]; then
    DAY_OUTPUT="Day completed!"
fi

# calculate number of days completed this week
DAYS_COMPLETED=$(( (TOTAL_WEEK_SECONDS - REMAINING_WEEK_SECONDS) / TOTAL_DAY_SECONDS ))

# visual output of 'days' completed
DAYS_COMPLETED_OUTPUT=""
for (( i=1; i<=DAYS; i++ )); do
    if [ $i -le $DAYS_COMPLETED ]; then
        DAYS_COMPLETED_OUTPUT+="●"
    else
        DAYS_COMPLETED_OUTPUT+="○"
    fi
done

# ----------------------------
# Menu bar output
# ----------------------------
echo "$DAYS_COMPLETED_OUTPUT | size=10"
echo "---"
echo "$DAY_OUTPUT"
echo "$WEEK_OUTPUT"
echo "---"
echo "Logs"
echo "--Session Logs | bash='open' param1='"$SESSION_LOGS"' terminal=false"
echo "--Logged Times | bash='open' param1='"$LOGGED_TIMES"' terminal=false"
echo "---"
echo "Refresh | refresh=true"
EOF
chmod +x ~/Library/Application\ Support/xbar/plugins/timr.30s.sh


# refresh xbar
osascript -e 'tell application "xbar" to quit' && open -a xbar


# allow uninstall
sudo chmod 755 ./timr_uninstall.sh                                                                      


echo "Timr installation complete."