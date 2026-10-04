#!/bin/bash
# Samples SleepyNotch's CPU, idle wake-ups and energy impact while it runs.
#
# Usage:  scripts/measure-energy.sh [seconds] [process-name]
#
# Start the app first (`swift run`), get it into the state you want to
# measure — e.g. music playing, notch collapsed, mouse away — then run this.
# Target for a collapsed notch: ~0% CPU and ~0 wake-ups per second.
set -euo pipefail

seconds=${1:-60}
name=${2:-SleepyNotch}
interval=5
samples=$(( seconds / interval ))
(( samples < 1 )) && samples=1

pid=$(pgrep -x "$name" | head -1 || true)
if [[ -z "$pid" ]]; then
    echo "$name isn't running. Start it with: swift run" >&2
    exit 1
fi

echo "Measuring $name (PID $pid) for ~${seconds}s. Don't touch the notch..."

# -c d reports wake-ups as a delta per sample. The first sample has no
# previous one to diff against, so it's dropped.
top -l $(( samples + 1 )) -s "$interval" -c d -pid "$pid" -stats pid,cpu,idlew,power \
    | awk -v pid="$pid" -v interval="$interval" '
        $1 == pid {
            seen++
            if (seen == 1) next
            cpu += $2; wake += $3; power += $4; n++
        }
        END {
            if (n == 0) { print "No samples collected."; exit 1 }
            printf "Average CPU:          %.2f %%\n", cpu / n
            printf "Idle wake-ups/second: %.1f\n", wake / (n * interval)
            printf "Energy impact:        %.2f\n", power / n
        }'
