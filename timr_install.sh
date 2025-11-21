#!/bin/bash
# Minimal Timr installer for macOS

echo "Installing Timr (user-local)..."

# --- 1. Create directories ---
mkdir -p ~/timr/logs
chmod 755 ~/timr ~/timr/logs

# --- 2. Create log files ---
touch ~/timr/logs/timr-log.txt ~/timr/logs/timr-daily-summary.txt
chmod 600 ~/timr/logs/*.txt

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

# --- 5. Create sleep/wake helper scripts ---
mkdir -p ~/Library/Scripts

cat << 'EOF' > ~/Library/Scripts/timr_sleep.sh
#!/bin/bash
~/timr/timr-logout.sh
EOF
chmod +x ~/Library/Scripts/timr_sleep.sh

cat << 'EOF' > ~/Library/Scripts/timr_wake.sh
#!/bin/bash
~/timr/timr-login.sh
EOF
chmod +x ~/Library/Scripts/timr_wake.sh

# --- 6. Create LaunchAgents ---

mkdir -p ~/Library/LaunchAgents

# Login agent
cat << 'EOF' > ~/Library/LaunchAgents/com.timr.login.plist
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key><string>com.timr.login</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/$(whoami)/timr/timr-login.sh</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.timr.login.plist

# SleepWatcher agent
cat << 'EOF' > ~/Library/LaunchAgents/com.timr.sleepwatcher.plist
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key><string>com.timr.sleepwatcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/sbin/sleepwatcher</string>
        <string>-V</string>
        <string>-s</string>
        <string>/Users/$(whoami)/Library/Scripts/timr_sleep.sh</string>
        <string>-w</string>
        <string>/Users/$(whoami)/Library/Scripts/timr_wake.sh</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.timr.sleepwatcher.plist

echo "Timr installation complete!"
echo "Logs: ~/timr/logs/timr-log.txt and timr-daily-summary.txt"
echo "SleepWatcher will handle auto-logout on sleep and login on wake."
