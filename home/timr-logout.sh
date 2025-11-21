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
