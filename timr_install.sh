#!/bin/bash
# timr_install.sh
# Complete macOS Timr with enhanced menu-bar display

echo "Starting Timr installation (user-local, no sudo)..."

# --- 1. Create directories in home folder ---
mkdir -p ~/timr
chmod 755 ~/timr

# --- 2. Create log files in Shared folder (optional) ---
mkdir -p ~/timr/logs
touch ~/timr/logs/timr-log.txt
chmod 600 ~/timr/logs/timr-log.txt

touch ~/timr/logs/timr-daily-summary.txt
chmod 600 ~/timr/logs/timr-daily-summary.txt

# --- 3. Create login script ---
cat << 'EOF' > ~/timr/timr-login.sh
#!/bin/bash
USERNAME=$(whoami)
LOGIN_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "$LOGIN_TIME" > /tmp/timr-last-login.txt
echo "$LOGIN_TIME LOGIN $USERNAME" >> ~/timr/logs/timr-log.txt
EOF
chmod +x ~/timr/timr-login.sh

# --- 4. Create logout script ---
cat << 'EOF' > ~/timr/timr-logout.sh
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

echo "$LOGOUT_TIME LOGOUT $USERNAME (Session: $DURATION seconds)" >> ~/timr/logs/timr-log.txt

if grep -q "^$DATE" ~/timr/logs/timr-daily-summary.txt; then
    OLD_TOTAL=$(grep "^$DATE" ~/timr/logs/timr-daily-summary.txt | awk '{print $2}')
    NEW_TOTAL=$((OLD_TOTAL + DURATION))
    sed -i '' "/^$DATE/c\\
$DATE $NEW_TOTAL
" ~/timr/logs/timr-daily-summary.txt
else
    echo "$DATE $DURATION" >> ~/timr/logs/timr-daily-summary.txt
fi

rm -f /tmp/timr-last-login.txt
EOF
chmod +x ~/timr/timr-logout.sh

# --- 5. Create weekly report script ---
cat << 'EOF' > ~/timr/timr-weekly-report.sh
#!/bin/bash
echo "Timr Weekly Session Totals:"
awk '{
    split($1,d,"-");
    cmd="date -jf %Y-%m-%d " $1 " +%U";
    cmd | getline week; close(cmd);
    total[week]+=$2
} END{
    for (w in total){
        t=total[w];
        h=int(t/3600); m=int((t%3600)/60); s=t%60;
        printf "Week %s: %02d:%02d:%02d\n", w,h,m,s
    }
}' ~/timr/logs/timr-daily-summary.txt
EOF
chmod +x ~/timr/timr-weekly-report.sh

# --- 6. Create login launch agent ---
mkdir -p ~/Library/LaunchAgents
cat << 'EOF' > ~/Library/LaunchAgents/com.timr.login.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.timr.login</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/$(whoami)/timr/timr-login.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.timr.login.plist

# --- 7. Create logout launch agent ---
cat << 'EOF' > ~/Library/LaunchAgents/com.timr.logout.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.timr.logout</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/$(whoami)/timr/timr-logout.sh</string>
    </array>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.timr.logout.plist

echo "Timr installation complete (user-local)!"
echo "Daily totals stored in ~/timr/logs/timr-daily-summary.txt"
echo "Weekly report available via:"
echo "~/timr/timr-weekly-report.sh"
echo "No sudo required, works entirely in your user account."
