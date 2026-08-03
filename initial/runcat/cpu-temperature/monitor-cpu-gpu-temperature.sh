#!/bin/sh
# RunCat Neo - CPU and GPU temperature monitor.
#
# Keeps one temperature-only sensor reader alive and forwards each five-second
# JSON sample to update-cpu-temperature.sh.

set -u

outputFile="${RUNCAT_OUT_FILE:-$HOME/.runcat/cpu-temperature.json}"
temperatureCommand="${RUNCAT_CPU_TEMPERATURE_COMMAND:-$HOME/.runcat/runcat-temperature}"
scriptDirectory=$(cd "$(dirname "$0")" && pwd)
updateScript="$scriptDirectory/update-cpu-temperature.sh"

if ! command -v "$temperatureCommand" >/dev/null 2>&1; then
    echo "CPU temperature provider not found: $temperatureCommand" >&2
    echo "Compile runcat-temperature.m and install it in ~/.runcat" >&2
    exit 1
fi

LC_ALL=C "$temperatureCommand" --interval 5 |
    while IFS= read -r snapshot; do
        printf '%s\n' "$snapshot" |
            RUNCAT_OUT_FILE="$outputFile" "$updateScript" --from-stdin
    done
