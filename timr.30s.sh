#!/bin/bash
# Timr xbar plugin
# Shows today and weekly totals

DAILY_FILE="$HOME/timr/logs/timr-daily-summary.txt"
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

# ----------------------------
# Menu bar output
# ----------------------------
echo "Day $TODAY_FMT - Week: $WEEK_FMT"
echo "---"
echo "This Week: $WEEK_FMT"
echo "---"
echo "Open Logs"
echo "--Daily Summary | bash=\"$DAILY_FILE\" terminal=false"
echo "--Full Log | bash=\"$HOME/timr/logs/timr-log.txt\" terminal=false"
echo "---"
echo "Refresh | refresh=true"
