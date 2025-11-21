#!/bin/bash
# install_time_tracker_final.sh
# Complete macOS Time Tracker with enhanced menu-bar display

echo "Starting Time Tracker installation..."

# --- 1. Create directories ---
mkdir -p /usr/local/time-tracker
chmod 755 /usr/local/time-tracker

# --- 2. Create log files ---
touch /Users/Shared/login-logout-log.txt
chmod 666 /Users/Shared/login-logout-log.txt

touch /Users/Shared/daily-session-summary.txt
chmod 666 /Users/Shared/daily-session-summary.txt

# --- 3. Create login script ---
cat << 'EOF' > /usr/local/time-tracker/log-login.sh
#!/bin/bash
USERNAME=$(whoami)
LOGIN_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "$LOGIN_TIME" > /tmp/last_login_time.txt
echo "$LOGIN_TIME LOGIN $USERNAME" >> /Users/Shared/login-logout-log.txt
EOF
chmod +x /usr/local/time-tracker/log-login.sh

# --- 4. Create logout script ---
cat << 'EOF' > /usr/local/time-tracker/log-logout.sh
#!/bin/bash
USERNAME=$(whoami)
LOGOUT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
DATE=$(date '+%Y-%m-%d')

if [ -f /tmp/last_login_time.txt ]; then
    LOGIN_TIME=$(cat /tmp/last_login_time.txt)
    LOGIN_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LOGIN_TIME" "+%s")
    LOGOUT_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LOGOUT_TIME" "+%s")
    DURATION=$((LOGOUT_EPOCH - LOGIN_EPOCH))
    HOURS=$((DURATION/3600))
    MINUTES=$(((DURATION%3600)/60))
    SECONDS=$((DURATION%60))
    DURATION_FORMATTED=$(printf "%02d:%02d:%02d" $HOURS $MINUTES $SECONDS)
else
    DURATION=0
    DURATION_FORMATTED="UNKNOWN"
fi

echo "$LOGOUT_TIME LOGOUT $USERNAME (Session: $DURATION_FORMATTED)" >> /Users/Shared/login-logout-log.txt

if grep -q "^$DATE" /Users/Shared/daily-session-summary.txt; then
    OLD_TOTAL=$(grep "^$DATE" /Users/Shared/daily-session-summary.txt | awk '{print $2}')
    NEW_TOTAL=$((OLD_TOTAL + DURATION))
    sed -i '' "/^$DATE/c\\
$DATE $NEW_TOTAL
" /Users/Shared/daily-session-summary.txt
else
    echo "$DATE $DURATION" >> /Users/Shared/daily-session-summary.txt
fi

rm -f /tmp/last_login_time.txt
EOF
chmod +x /usr/local/time-tracker/log-logout.sh

# --- 5. Create weekly report script ---
cat << 'EOF' > /usr/local/time-tracker/weekly-report.sh
#!/bin/bash
echo "Weekly Session Totals:"
awk '{
    split($1,d,"-"); 
    cmd="date -jf %Y-%m-%d " $1 " +%U"; 
    cmd | getline week; close(cmd); 
    total[week]+= $2
} END{
    for (w in total){
        t=total[w];
        h=int(t/3600); m=int((t%3600)/60); s=t%60;
        printf "Week %s: %02d:%02d:%02d\n", w,h,m,s
    }
}' /Users/Shared/daily-session-summary.txt
EOF
chmod +x /usr/local/time-tracker/weekly-report.sh

# --- 6. Create login launch agent ---
mkdir -p ~/Library/LaunchAgents
cat << 'EOF' > ~/Library/LaunchAgents/com.time-tracker.login.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.time-tracker.login</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/time-tracker/log-login.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.time-tracker.login.plist

# --- 7. Create logout launch agent ---
cat << 'EOF' > ~/Library/LaunchAgents/com.time-tracker.logout.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.time-tracker.logout</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/time-tracker/log-logout.sh</string>
    </array>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.time-tracker.logout.plist

# --- 8. Install enhanced xbar menu-bar plugin ---
XBAR_PLUGIN_DIR=~/Library/Application\ Support/xbar/plugins
mkdir -p "$XBAR_PLUGIN_DIR"

cat << 'EOF' > "$XBAR_PLUGIN_DIR/mac-time-tracker.1m.sh"
#!/bin/bash
LOG_FILE="/Users/Shared/daily-session-summary.txt"
TODAY=$(date '+%Y-%m-%d')

# Today's total
TODAY_SECONDS=$(grep "^$TODAY" "$LOG_FILE" | awk '{print $2}')
[ -z "$TODAY_SECONDS" ] && TODAY_SECONDS=0
H=$((TODAY_SECONDS/3600))
M=$(((TODAY_SECONDS%3600)/60))
S=$((TODAY_SECONDS%60))
TODAY_FORMATTED=$(printf "%02d:%02d:%02d" $H $M $S)

# Current week's total
WEEK_TOTAL=$(awk -v week=$(date +%U) '{
    split($1,d,"-");
    cmd="date -jf %Y-%m-%d " $1 " +%U";
    cmd | getline w; close(cmd);
    if (w==week) total+=$2
} END{print total}' "$LOG_FILE")
[ -z "$WEEK_TOTAL" ] && WEEK_TOTAL=0
WH=$((WEEK_TOTAL/3600))
WM=$(((WEEK_TOTAL%3600)/60))
WS=$((WEEK_TOTAL%60))
WEEK_FORMATTED=$(printf "%02d:%02d:%02d" $WH $WM $WS)

# Menu bar output
echo "⌚ Today: $TODAY_FORMATTED | Week: $WEEK_FORMATTED"
echo "---"
echo "Daily Log: $TODAY_FORMATTED"
echo "Weekly Log: $WEEK_FORMATTED"
echo "Refresh | refresh=true"
EOF

chmod +x "$XBAR_PLUGIN_DIR/mac-time-tracker.1m.sh"

echo "Installation complete!"
echo "1. Login/logout tracking is active."
echo "2. Enhanced menu-bar plugin installed via xbar."
echo "   Open xbar and refresh plugins to see daily + weekly usage."
echo "3. Weekly report available via:"
echo "/usr/local/time-tracker/weekly-report.sh"
