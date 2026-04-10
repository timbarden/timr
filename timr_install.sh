#!/bin/bash
# Timr installer for macOS

# Exit immediately if any command fails, so a half-broken install can't
# silently continue past (e.g.) a failed mkdir or failed heredoc write.
set -e


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
if [ ! -d "/Applications/xbar.app" ] && [ ! -d "$HOME/Applications/xbar.app" ]; then
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
chmod 755 ~/Library/Logs/timr


# Create log files if they don't already exist
if [ ! -f ~/Library/Logs/timr/sessions.log ]; then
    touch ~/Library/Logs/timr/sessions.log
fi
if [ ! -f ~/Library/Logs/timr/developer.log ]; then
    touch ~/Library/Logs/timr/developer.log
fi
chmod 600 ~/Library/Logs/timr/*.log


# Create scripts
mkdir -p ~/Library/Scripts/timr


# Create start script ---
# Accepts an optional reason argument (e.g. login, wake, resume) that is
# written into sessions.log so each line explains which trigger fired it.
# Honours the pause flag: if the user has manually paused Timr, lid-close
# and subsequent wake events must not silently resume the timer.
cat << 'EOF' > ~/Library/Scripts/timr/timr-start.sh
#!/bin/bash
REASON=${1:-unknown}
USERNAME=$(whoami)
NOW=$(date '+%Y-%m-%d %H:%M:%S')
PAUSE_FLAG="$HOME/Library/Application Support/timr/paused"

# Honour manual pause: if the user paused Timr, a wake or login must not
# re-create the in-flight marker. The pause flag is cleared explicitly via
# the xbar Resume action.
if [ -f "$PAUSE_FLAG" ]; then
    echo "$NOW START $REASON $USERNAME (skipped: paused)" >> ~/Library/Logs/timr/sessions.log
    exit 0
fi

# Only set the in-flight marker if no session is already open, so a
# wake-after-login doesn't clobber the original login timestamp.
[ -f /tmp/timr-last.txt ] || echo "$NOW" > /tmp/timr-last.txt
echo "$NOW START $REASON $USERNAME" >> ~/Library/Logs/timr/sessions.log
EOF
chmod +x ~/Library/Scripts/timr/timr-start.sh


# Create stop script ---
# Accepts an optional reason argument (e.g. sleep, shutdown, pause). If no
# in-flight marker exists (already stopped, or called during pause), the
# script still logs the STOP line for the audit trail but does not touch
# developer.log. Sessions that span midnight are split so each calendar
# day gets credited only the seconds that actually fell within it.
cat << 'EOF' > ~/Library/Scripts/timr/timr-stop.sh
#!/bin/bash
REASON=${1:-unknown}
USERNAME=$(whoami)
NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date '+%s')
DEV_LOG=~/Library/Logs/timr/developer.log

if [ -f /tmp/timr-last.txt ]; then
    LOGIN_TIME=$(cat /tmp/timr-last.txt)
    LOGIN_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LOGIN_TIME" "+%s")
    DURATION=$((NOW_EPOCH - LOGIN_EPOCH))
else
    LOGIN_EPOCH=0
    DURATION=0
fi

echo "$NOW STOP $REASON $USERNAME (Session: $DURATION seconds)" >> ~/Library/Logs/timr/sessions.log

# Accumulate `$2` seconds into the line for date `$1` in developer.log,
# creating the line if it doesn't exist.
accumulate_day() {
    local day=$1
    local secs=$2
    if grep -q "^$day" "$DEV_LOG"; then
        local old_total
        old_total=$(grep "^$day" "$DEV_LOG" | awk '{print $2}')
        local new_total=$((old_total + secs))
        sed -i '' "/^$day/c\\
$day $new_total
" "$DEV_LOG"
    else
        echo "$day $secs" >> "$DEV_LOG"
    fi
}

# Only accumulate into developer.log if there was an actual session open.
# A STOP with no marker (e.g. a redundant shutdown trap after pause) must
# not add a zero-duration entry.
if [ "$DURATION" -gt 0 ]; then
    # Walk the session day-by-day. For each iteration, segment_start is
    # somewhere inside a calendar day, and segment_end is either the next
    # midnight or the real session end, whichever comes first. The day the
    # segment belongs to is derived from segment_start. Using `date -v+1d`
    # to advance by one day handles DST transitions correctly (86400 would
    # misbehave on DST change days).
    segment_start=$LOGIN_EPOCH
    while [ "$segment_start" -lt "$NOW_EPOCH" ]; do
        day=$(date -r "$segment_start" "+%Y-%m-%d")
        next_midnight=$(date -j -v+1d -f "%Y-%m-%d %H:%M:%S" "$day 00:00:00" "+%s")
        if [ "$next_midnight" -gt "$NOW_EPOCH" ]; then
            segment_end=$NOW_EPOCH
        else
            segment_end=$next_midnight
        fi
        accumulate_day "$day" "$((segment_end - segment_start))"
        segment_start=$segment_end
    done
fi

rm -f /tmp/timr-last.txt
EOF
chmod +x ~/Library/Scripts/timr/timr-stop.sh


# Create shutdown-watch script ---
# Persistent wrapper that traps SIGTERM (sent by launchd on logout/shutdown)
# and runs timr-stop.sh to close the in-flight session before the system
# goes down. The `sleep & wait` pattern is required because bash does not
# process signals while a foreground builtin is running — `wait` is
# interruptible, so the trap fires promptly.
cat << 'EOF' > ~/Library/Scripts/timr/timr-shutdown-watch.sh
#!/bin/bash
on_term() {
    if [ -f /tmp/timr-last.txt ]; then
        "$HOME/Library/Scripts/timr/timr-stop.sh" shutdown
    fi
    exit 0
}
trap on_term TERM INT
while :; do
    sleep 3600 &
    wait $!
done
EOF
chmod +x ~/Library/Scripts/timr/timr-shutdown-watch.sh


# Create LaunchAgents ---
mkdir -p ~/Library/LaunchAgents


# Resolve sleepwatcher binary (Apple Silicon vs Intel Homebrew prefix)
if [ -x "/opt/homebrew/opt/sleepwatcher/sbin/sleepwatcher" ]; then
    SLEEPWATCHER_BIN="/opt/homebrew/opt/sleepwatcher/sbin/sleepwatcher"
else
    SLEEPWATCHER_BIN="/usr/local/opt/sleepwatcher/sbin/sleepwatcher"
fi

# Login agent
# NOTE: heredoc is unquoted so $HOME is expanded at install time.
# launchd does NOT expand $(...) or $VAR inside ProgramArguments, so paths
# must be fully resolved before being written to the plist.
cat << EOF > ~/Library/LaunchAgents/com.timr.login.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.timr.login</string>
        <key>ProgramArguments</key>
        <array>
            <string>${HOME}/Library/Scripts/timr/timr-start.sh</string>
            <string>login</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
    </dict>
</plist>
EOF

# Create sleepwatcher agent
cat << EOF > ~/Library/LaunchAgents/com.timr.sleepwatcher.plist
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.timr.sleepwatcher</string>
        <key>ProgramArguments</key>
        <array>
            <string>${SLEEPWATCHER_BIN}</string>
            <!-- Verbose mode flag (shows detailed logging of sleepwatcher activity) -->
            <string>-V</string>
            <!-- Sleep flag. sleepwatcher passes the command through /bin/sh,
                 so we can include the reason argument inline. -->
            <string>-s</string>
            <string>${HOME}/Library/Scripts/timr/timr-stop.sh sleep</string>
            <!-- Wake flag, same mechanism. -->
            <string>-w</string>
            <string>${HOME}/Library/Scripts/timr/timr-start.sh wake</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
    </dict>
</plist>
EOF

# Shutdown-watch agent
# Persistent agent that runs timr-shutdown-watch.sh. launchd sends SIGTERM
# to this process on logout/shutdown, the script's trap runs timr-stop.sh,
# and the in-flight session is closed before the system goes down.
cat << EOF > ~/Library/LaunchAgents/com.timr.shutdown.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.timr.shutdown</string>
        <key>ProgramArguments</key>
        <array>
            <string>${HOME}/Library/Scripts/timr/timr-shutdown-watch.sh</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
    </dict>
</plist>
EOF


# Load the agents using the modern `launchctl bootstrap`/`bootout` API.
# The legacy `load`/`unload` commands still work but print deprecation
# warnings on Sonoma+. `bootout` errors if the agent isn't loaded, so we
# suppress errors — first install is a valid case. `set -e` is briefly
# disabled around bootout since its failure is expected.
GUI_DOMAIN="gui/$(id -u)"
set +e
launchctl bootout "$GUI_DOMAIN/com.timr.login" 2>/dev/null
launchctl bootout "$GUI_DOMAIN/com.timr.sleepwatcher" 2>/dev/null
launchctl bootout "$GUI_DOMAIN/com.timr.shutdown" 2>/dev/null
set -e

launchctl bootstrap "$GUI_DOMAIN" ~/Library/LaunchAgents/com.timr.login.plist
launchctl bootstrap "$GUI_DOMAIN" ~/Library/LaunchAgents/com.timr.sleepwatcher.plist
launchctl bootstrap "$GUI_DOMAIN" ~/Library/LaunchAgents/com.timr.shutdown.plist


# create xbar plugin
mkdir -p ~/Library/Application\ Support/xbar/plugins
cat << 'EOF' > ~/Library/Application\ Support/xbar/plugins/timr.30s.sh
#!/bin/bash
# Timr xbar plugin
# Shows day and weekly times
#
# <xbar.title>Timr</xbar.title>
# <xbar.desc>Automatic time tracking for macOS. Configure your weekly hour target and number of work days from the Timr dropdown menu.</xbar.desc>

# ----------------------------
# Config
# ----------------------------
# Config lives in ~/Library/Application Support/timr/config as simple
# KEY=VALUE lines. We deliberately do NOT use xbar's own vars.json system
# here: xbar caches vars.json in memory and only re-reads it when the user
# edits values through the xbar preferences UI. Writing vars.json directly
# from a menu-action handler has no effect until xbar is fully restarted,
# which defeats the point of an in-menu settings picker. Our own config
# file is read fresh on every plugin invocation, so dropdown changes take
# effect instantly.
CONFIG_DIR="$HOME/Library/Application Support/timr"
CONFIG_FILE="$CONFIG_DIR/config"
PAUSE_FLAG="$CONFIG_DIR/paused"
LAST_PROMPT_FILE="$CONFIG_DIR/last-prompt"
START_SCRIPT="$HOME/Library/Scripts/timr/timr-start.sh"
STOP_SCRIPT="$HOME/Library/Scripts/timr/timr-stop.sh"
mkdir -p "$CONFIG_DIR"

# Defaults (used on first run or if a key is missing from the config file)
HOURS=35
DAYS=5

# Read config if present. Parsed defensively rather than `source`d so a
# corrupted/tampered file cannot execute arbitrary code.
if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            HOURS) HOURS="$value" ;;
            DAYS)  DAYS="$value" ;;
        esac
    done < "$CONFIG_FILE"
fi

# ----------------------------
# Menu-action handlers
# ----------------------------
# xbar invokes menu items as `bash=$0 param1=<action> param2=<value>`. When
# the plugin is re-entered with a known action in $1, we update the config
# file and exit — the `refresh=true` flag on the menu line reloads the
# plugin afterwards, and the next read picks up the new values.

is_positive_number() {
    # Accept integer or decimal, must parse as > 0. Used for HOURS, where
    # values like 37.5 are legitimate.
    [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    awk -v v="$1" 'BEGIN { exit !(v > 0) }'
}

is_positive_integer() {
    # Integer only, > 0. Used for DAYS, because bash integer arithmetic
    # (`$((TOTAL/DAYS))`) can't handle decimals and we'd error out on
    # render if a decimal slipped into the config.
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

write_config() {
    printf 'HOURS=%s\nDAYS=%s\n' "$1" "$2" > "$CONFIG_FILE"
}

prompt_number() {
    # $1 = dialog prompt, $2 = default value. Echoes the entered value on
    # stdout, or nothing if the user cancelled.
    osascript -e "display dialog \"$1\" default answer \"$2\" with title \"Timr\"" \
              -e 'text returned of result' 2>/dev/null
}

do_pause() {
    # Close the current session cleanly, then raise the pause flag. The
    # flag must exist before any subsequent wake/login event so those
    # scripts know to skip re-creating the marker.
    "$STOP_SCRIPT" pause
    touch "$PAUSE_FLAG"
}

do_resume() {
    # Clear the flag first so the start script is allowed to create a new
    # marker, then start a fresh session.
    rm -f "$PAUSE_FLAG"
    "$START_SCRIPT" resume
}

case "$1" in
    set-hours)
        is_positive_number "$2" && write_config "$2" "$DAYS"
        exit 0
        ;;
    set-hours-custom)
        new=$(prompt_number "Weekly hour target:" "$HOURS")
        [ -n "$new" ] && is_positive_number "$new" && write_config "$new" "$DAYS"
        exit 0
        ;;
    set-days)
        is_positive_integer "$2" && write_config "$HOURS" "$2"
        exit 0
        ;;
    set-days-custom)
        new=$(prompt_number "Work days per week (whole number):" "$DAYS")
        [ -n "$new" ] && is_positive_integer "$new" && write_config "$HOURS" "$new"
        exit 0
        ;;
    pause)
        do_pause
        exit 0
        ;;
    resume)
        do_resume
        exit 0
        ;;
esac

# ----------------------------
# Paused state + resume prompt
# ----------------------------
# If the pause flag exists, Timr is in manual-pause mode. The flag's mtime
# is the moment pause was activated, so we use `stat` to compute how long
# we've been paused without needing to store the timestamp in the file.
PAUSED=0
PAUSED_SINCE=0
if [ -f "$PAUSE_FLAG" ]; then
    PAUSED=1
    PAUSED_SINCE=$(stat -f %m "$PAUSE_FLAG" 2>/dev/null || echo 0)
fi

# Resume prompt: if paused for more than 60s AND there's been recent HID
# activity AND we haven't already prompted in the last 5 minutes, pop a
# dialog asking whether to resume. The rate limit prevents spam if the
# user dismisses the dialog and keeps working. HIDIdleTime is reported in
# nanoseconds by ioreg — divide to get seconds.
if [ "$PAUSED" = "1" ]; then
    NOW_EPOCH_PROMPT=$(date +%s)
    PAUSED_FOR=$((NOW_EPOCH_PROMPT - PAUSED_SINCE))
    if [ "$PAUSED_FOR" -gt 60 ]; then
        IDLE_NS=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print $NF; exit}')
        IDLE_SECONDS=$(( ${IDLE_NS:-999999999999} / 1000000000 ))

        LAST_PROMPT=0
        [ -f "$LAST_PROMPT_FILE" ] && LAST_PROMPT=$(stat -f %m "$LAST_PROMPT_FILE" 2>/dev/null || echo 0)
        SINCE_PROMPT=$((NOW_EPOCH_PROMPT - LAST_PROMPT))

        if [ "$IDLE_SECONDS" -lt 10 ] && [ "$SINCE_PROMPT" -gt 300 ]; then
            touch "$LAST_PROMPT_FILE"
            RESPONSE=$(osascript \
                -e 'display dialog "Timr is paused. Resume the timer?" buttons {"Stay paused","Resume"} default button "Resume" with title "Timr"' \
                -e 'button returned of result' 2>/dev/null)
            if [ "$RESPONSE" = "Resume" ]; then
                do_resume
                PAUSED=0
            fi
        fi
    fi
fi

DEV_LOGS="$HOME/Library/Logs/timr/developer.log"
SESSION_LOGS="$HOME/Library/Logs/timr/sessions.log"
TEMP_FILE="/tmp/timr-last.txt"
TODAY=$(date "+%Y-%m-%d")

# Today's total
TODAY_SECONDS=0
if grep -q "^$TODAY" "$DEV_LOGS" 2>/dev/null; then
    TODAY_SECONDS=$(grep "^$TODAY" "$DEV_LOGS" | awk '{print $2}')
fi

# Add current session
if [ -f "$TEMP_FILE" ]; then
    LOGIN_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(cat $TEMP_FILE)" "+%s")
    NOW_EPOCH=$(date "+%s")
    TODAY_SECONDS=$((TODAY_SECONDS + NOW_EPOCH - LOGIN_EPOCH))
fi

# Weekly total, starting Monday. Filter by year-qualified week (e.g.
# "2026-15") rather than bare week number, so entries from the same week
# number in a previous year don't contaminate the current week's total.
WEEK=$(date +%Y-%W)
WEEK_SECONDS=$(awk -v week="$WEEK" '
{
    cmd="date -jf %Y-%m-%d " $1 " +%Y-%W";
    cmd | getline w; close(cmd);
    if (w == week) total+=$2;
}
END { print total }
' "$DEV_LOGS" 2>/dev/null)

[ -z "$WEEK_SECONDS" ] && WEEK_SECONDS=0

# Add current session to week
if [ -f "$TEMP_FILE" ]; then
    WEEK_SECONDS=$((WEEK_SECONDS + NOW_EPOCH - LOGIN_EPOCH))
fi

# Safety fallbacks. HOURS may be decimal; DAYS must be a positive integer
# because bash integer arithmetic (used below) can't divide by a decimal.
# If a stale/tampered config produces a non-integer DAYS, fall back to 5
# rather than erroring out at render time.
[ -z "$HOURS" ] && HOURS=35
[[ "$DAYS" =~ ^[0-9]+$ ]] && [ "$DAYS" -gt 0 ] || DAYS=5

# HOURS may be decimal (e.g. 37.5), so use awk instead of bash arithmetic
# which is integer-only. Result is truncated to whole seconds.
TOTAL_WEEK_SECONDS=$(awk -v h="$HOURS" 'BEGIN { printf "%d", h * 3600 }')
REMAINING_WEEK_SECONDS=$((TOTAL_WEEK_SECONDS - WEEK_SECONDS))
rwh=$((REMAINING_WEEK_SECONDS/3600))
rwm=$(((REMAINING_WEEK_SECONDS%3600)/60))
# show overtime as positive value
if [ $REMAINING_WEEK_SECONDS -lt 0 ]; then
    rwh=$(( -rwh ))
    rwm=$(( -rwm ))
fi
WEEK_REMAIN=$(printf "%2dh %02dmin" "$rwh" "$rwm")
if [ $REMAINING_WEEK_SECONDS -lt 0 ]; then
    WEEK_OUTPUT="Week completed! Overtime: $WEEK_REMAIN"
else
    WEEK_OUTPUT="Week remaining: $WEEK_REMAIN"
fi

# calculate a day remain value based on TOTAL_WEEK_SECONDS/DAYS
TOTAL_DAY_SECONDS=$((TOTAL_WEEK_SECONDS/DAYS))
REMAINING_DAY_SECONDS=$((TOTAL_DAY_SECONDS - TODAY_SECONDS))
rdh=$((REMAINING_DAY_SECONDS/3600))
rdm=$(((REMAINING_DAY_SECONDS%3600)/60))
DAY_REMAIN=$(printf "%2dh %02dmin" "$rdh" "$rdm")
# Ensure day remaining never exceeds week remaining (compare seconds, not
# formatted strings — formatted strings compare lexically and produce wrong
# answers like " 7h 00min" < "12h 00min").
if [ $REMAINING_DAY_SECONDS -gt $REMAINING_WEEK_SECONDS ]; then
    DAY_REMAIN=$WEEK_REMAIN
fi
DAY_OUTPUT="Day remaining: $DAY_REMAIN"
if [ $REMAINING_DAY_SECONDS -lt 0 ]; then
    DAY_OUTPUT="Day completed!"
fi

# Number of full days completed this week, clamped to [0, DAYS] so
# overtime doesn't produce a count higher than the dots we render.
DAYS_COMPLETED=$(( WEEK_SECONDS / TOTAL_DAY_SECONDS ))
if [ $DAYS_COMPLETED -gt $DAYS ]; then DAYS_COMPLETED=$DAYS; fi
if [ $DAYS_COMPLETED -lt 0 ]; then DAYS_COMPLETED=0; fi

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
if [ "$PAUSED" = "1" ]; then
    echo "⏸ $DAYS_COMPLETED_OUTPUT | size=10"
else
    echo "$DAYS_COMPLETED_OUTPUT | size=10"
fi
echo "---"
if [ "$PAUSED" = "1" ]; then
    echo "Status: Paused"
fi
echo "$DAY_OUTPUT"
echo "$WEEK_OUTPUT"
echo "---"
# Pause/Resume toggle — label and action depend on current state.
if [ "$PAUSED" = "1" ]; then
    printf -- "Resume timer | bash=\"%s\" param1=resume terminal=false refresh=true\n" "$0"
else
    printf -- "Pause timer | bash=\"%s\" param1=pause terminal=false refresh=true\n" "$0"
fi
echo "---"
echo "Settings"
# Weekly hour target submenu. Each preset re-invokes this plugin with
# `set-hours <value>` and triggers a refresh so the new target takes effect
# on the spot.
printf -- "--Weekly hours: %sh\n" "$HOURS"
for preset in 20 25 30 35 37.5 40; do
    marker=" "
    [ "$preset" = "$HOURS" ] && marker="✓"
    printf -- "----%s %sh | bash=\"%s\" param1=set-hours param2=%s terminal=false refresh=true\n" \
        "$marker" "$preset" "$0" "$preset"
done
printf -- "----Custom... | bash=\"%s\" param1=set-hours-custom terminal=false refresh=true\n" "$0"
# Days per week submenu.
printf -- "--Days per week: %s\n" "$DAYS"
for preset in 4 5 6; do
    marker=" "
    [ "$preset" = "$DAYS" ] && marker="✓"
    printf -- "----%s %s | bash=\"%s\" param1=set-days param2=%s terminal=false refresh=true\n" \
        "$marker" "$preset" "$0" "$preset"
done
printf -- "----Custom... | bash=\"%s\" param1=set-days-custom terminal=false refresh=true\n" "$0"
echo "---"
echo "Logs"
printf -- "--Session Logs | bash=open param1=%s terminal=false\n" "$SESSION_LOGS"
printf -- "--Developer Logs | bash=open param1=%s terminal=false\n" "$DEV_LOGS"
echo "---"
echo "Refresh | refresh=true"
EOF
chmod +x ~/Library/Application\ Support/xbar/plugins/timr.30s.sh


# refresh xbar (quit if running, then relaunch — use `;` so relaunch still
# happens when xbar isn't running yet)
osascript -e 'tell application "xbar" to quit' 2>/dev/null; open -a xbar


echo "Timr installation complete."