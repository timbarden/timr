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
