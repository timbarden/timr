#!/bin/bash
USERNAME=$(whoami)
LOGIN_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "$LOGIN_TIME" > /tmp/timr-last-login.txt
echo "$LOGIN_TIME LOGIN $USERNAME" >> ~/timr/logs/timr-log.txt
