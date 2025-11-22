#!/bin/bash
# Timr installer for macOS

echo "Installing Timr..."

# --- 1. Create directories ---
mkdir -p ~/Library/Logs/timr
chmod 755 ~/Library ~/Library/Logs ~/Library/Logs/timr

# --- 2. Create log files ---
touch ~/Library/Logs/timr/timr-log.txt 
touch ~/Library/Logs/timr/timr-daily-summary.txt
chmod 600 ~/Library/Logs/timr/*.txt


# Create scripts
mkdir -p ~/Library/Scripts/timr


# Create login script ---
cat << 'EOF' > ~/Library/Scripts/timr/timr-start.sh
#!/bin/bash
USERNAME=$(whoami)
LOGIN_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "$LOGIN_TIME" > /tmp/timr-last-login.txt
echo "$LOGIN_TIME LOGIN $USERNAME" >> ~/Library/Logs/timr/timr-log.txt
EOF
chmod +x ~/Library/Scripts/timr/timr-start.sh


# Create stop script ---
cat << 'EOF' > ~/Library/Scripts/timr/timr-stop.sh
#!/bin/bash
USERNAME=$(whoami)
LOGOUT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
DATE=$(date '+%Y-%m-%d')

if [ -f /tmp/timr-last-login.txt ]; then
    LOGIN_TIME=$(cat /tmp/timr-last-login.txt)
    LOGIN_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LOGIN_TIME" "+%s")
    LOGOUT_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LOGOUT_TIME" "+%s")
    DURATION=$((LOGOUT_EPOCH - LOGIN_EPOCH))
else
    DURATION=0
fi

echo "$LOGOUT_TIME LOGOUT $USERNAME (Session: $DURATION seconds)" >> ~/Library/Logs/timr/timr-log.txt

if grep -q "^$DATE" ~/Library/Logs/timr/timr-daily-summary.txt; then
    OLD_TOTAL=$(grep "^$DATE" ~/Library/Logs/timr/timr-daily-summary.txt | awk '{print $2}')
    NEW_TOTAL=$((OLD_TOTAL + DURATION))
    sed -i '' "/^$DATE/c\\
$DATE $NEW_TOTAL
" ~/Library/Logs/timr/timr-daily-summary.txt
else
    echo "$DATE $DURATION" >> ~/Library/Logs/timr/timr-daily-summary.txt
fi

rm -f /tmp/timr-last-login.txt
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
            <string>-V</string>
            <string>-s</string>
            <string>/Users/$(whoami)/Library/Scripts/timr/timr-stop.sh</string>
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

DAILY_FILE="$HOME/Library/Logs/timr/timr-daily-summary.txt"
FULL_LOG_FILE="$HOME/Library/Logs/timr/timr-log.txt"
LOGIN_FILE="/tmp/timr-last-login.txt"
TODAY=$(date "+%Y-%m-%d")

# Today's total
TODAY_SECONDS=0
if grep -q "^$TODAY" "$DAILY_FILE" 2>/dev/null; then
    TODAY_SECONDS=$(grep "^$TODAY" "$DAILY_FILE" | awk '{print $2}')
fi

# Add current session
if [ -f "$LOGIN_FILE" ]; then
    LOGIN_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(cat $LOGIN_FILE)" "+%s")
    NOW_EPOCH=$(date "+%s")
    TODAY_SECONDS=$((TODAY_SECONDS + NOW_EPOCH - LOGIN_EPOCH))
fi

# Format HH:MM:SS
h=$((TODAY_SECONDS/3600))
m=$(((TODAY_SECONDS%3600)/60))
TODAY_FMT=$(printf "%02d:%02d" "$h" "$m")

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
' "$DAILY_FILE" 2>/dev/null)

[ -z "$WEEK_SECONDS" ] && WEEK_SECONDS=0

# Add current session to week
if [ -f "$LOGIN_FILE" ]; then
    WEEK_SECONDS=$((WEEK_SECONDS + NOW_EPOCH - LOGIN_EPOCH))
fi

wh=$((WEEK_SECONDS/3600))
wm=$(((WEEK_SECONDS%3600)/60))
WEEK_FMT=$(printf "%02d:%02d" "$wh" "$wm")

DAYS=5
HOURS=35

# delete the week_fmt from the total hours so it counts down
TOTAL_WEEK_SECONDS=$((HOURS * 3600))
REMAINING_WEEK_SECONDS=$((TOTAL_WEEK_SECONDS - WEEK_SECONDS))
rwh=$((REMAINING_WEEK_SECONDS/3600))
rwm=$(((REMAINING_WEEK_SECONDS%3600)/60))
WEEK_REMAIN=$(printf "%02d:%02d" "$rwh" "$rwm")
WEEK_OUTPUT="Week remaining: $WEEK_REMAIN"
if [ $REMAINING_WEEK_SECONDS -lt 0 ]; then
    WEEK_OUTPUT="Week completed! Overtime: $WEEK_REMAIN"
fi

# calculate a day remain value based on TOTAL_WEEK_SECONDS/5
TOTAL_DAY_SECONDS=$((TOTAL_WEEK_SECONDS/DAYS))
REMAINING_DAY_SECONDS=$((TOTAL_DAY_SECONDS - TODAY_SECONDS))
rdh=$((REMAINING_DAY_SECONDS/3600))
rdm=$(((REMAINING_DAY_SECONDS%3600)/60))
DAY_REMAIN=$(printf "%02d:%02d" "$rdh" "$rdm")
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
echo "Open Logs"
echo "--Daily Summary | bash='open' param1='"$DAILY_FILE"' terminal=false"
echo "--Full Log | bash='open' param1='"$FULL_LOG_FILE"' terminal=false"
echo "---"
echo "Refresh | refresh=true"
EOF
chmod +x ~/Library/Application\ Support/xbar/plugins/timr.30s.sh

# refresh xbar
osascript -e 'tell application "xbar" to quit' && open -a xbar

# allow uninstall
sudo chmod 755 ./timr_uninstall.sh                                                                      

echo "Timr installation complete."