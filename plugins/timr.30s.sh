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

DAYS=5
HOURS=35

# delete the week_fmt from the total hours so it counts down
TOTAL_WEEK_SECONDS=$((HOURS * 3600))
REMAINING_WEEK_SECONDS=$((TOTAL_WEEK_SECONDS - WEEK_SECONDS))
rwh=$((REMAINING_WEEK_SECONDS/3600))
rwm=$(((REMAINING_WEEK_SECONDS%3600)/60))
WEEK_REMAIN=$(printf "%02d:%02d" "$rwh" "$rwm")

# calculate a day remain value based on TOTAL_WEEK_SECONDS/5
TOTAL_DAY_SECONDS=$((TOTAL_WEEK_SECONDS/DAYS))
REMAINING_DAY_SECONDS=$((TOTAL_DAY_SECONDS - TODAY_SECONDS))
rdh=$((REMAINING_DAY_SECONDS/3600))
rdm=$(((REMAINING_DAY_SECONDS%3600)/60))
DAY_REMAIN=$(printf "%02d:%02d" "$rdh" "$rdm")

# calculate number of days completed this week based on REMAINING_WEEK_SECONDS and TOTAL_WEEK_SECONDS
DAYS_COMPLETED=$(( (TOTAL_WEEK_SECONDS - REMAINING_WEEK_SECONDS) / TOTAL_DAY_SECONDS ))

# for each day in DAYS, print a filled circle if day is completed, else empty circle
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
echo "Day remaining: $DAY_REMAIN"
echo "Week remaining: $WEEK_REMAIN"
echo "---"
echo "Open Logs"
echo "--Daily Summary | bash=\"$DAILY_FILE\" terminal=false"
echo "--Full Log | bash=\"$HOME/timr/logs/timr-log.txt\" terminal=false"
echo "---"
echo "Refresh | refresh=true"
