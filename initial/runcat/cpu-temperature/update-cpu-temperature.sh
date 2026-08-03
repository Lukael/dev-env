#!/bin/sh
# RunCat Neo - CPU temperature sample.
#
# Reads CPU and GPU temperatures from the lightweight runcat-temperature
# provider and writes a Custom Metrics JSON snapshot.

set -eu

outputFile="${RUNCAT_OUT_FILE:-$HOME/.runcat/cpu-temperature.json}"
temperatureCommand="${RUNCAT_CPU_TEMPERATURE_COMMAND:-$HOME/.runcat/runcat-temperature}"

case "${1:-}" in
    --from-stdin)
        rawTemperature=$(cat)
        ;;
    '')
        if ! command -v "$temperatureCommand" >/dev/null 2>&1; then
            echo "CPU temperature provider not found: $temperatureCommand" >&2
            echo "Compile runcat-temperature.m and install it in ~/.runcat" >&2
            exit 1
        fi
        rawTemperature=$(LC_ALL=C "$temperatureCommand")
        ;;
    *)
        echo "Usage: $0 [--from-stdin]" >&2
        exit 1
        ;;
esac

cpuTemperature=$(printf '%s\n' "$rawTemperature" \
        | sed -nE 's/.*"cpu_temp"[[:space:]]*:[[:space:]]*([-+]?[0-9]+([.][0-9]+)?).*/\1/p' \
        | head -n 1)
gpuTemperature=$(printf '%s\n' "$rawTemperature" \
        | sed -nE 's/.*"gpu_temp"[[:space:]]*:[[:space:]]*([-+]?[0-9]+([.][0-9]+)?).*/\1/p' \
        | head -n 1)
if [ -z "$cpuTemperature" ] || [ -z "$gpuTemperature" ]; then
    echo "Failed to read numeric CPU and GPU temperatures from: $rawTemperature" >&2
    exit 1
fi

if ! awk -v cpu="$cpuTemperature" -v gpu="$gpuTemperature" \
    'BEGIN { exit !(cpu > 0 && cpu < 150 && gpu > 0 && gpu < 150) }'; then
    echo "CPU or GPU temperature is outside the expected range" >&2
    exit 1
fi

formattedCPUTemperature=$(awk -v temperature="$cpuTemperature" 'BEGIN { printf "%.1f°C", temperature }')
formattedGPUTemperature=$(awk -v temperature="$gpuTemperature" 'BEGIN { printf "%.1f°C", temperature }')
normalizedCPUValue=$(awk -v temperature="$cpuTemperature" 'BEGIN {
    value = temperature / 100
    if (value < 0) value = 0
    if (value > 1) value = 1
    printf "%.3f", value
}')
normalizedGPUValue=$(awk -v temperature="$gpuTemperature" 'BEGIN {
    value = temperature / 100
    if (value < 0) value = 0
    if (value > 1) value = 1
    printf "%.3f", value
}')
lastUpdatedDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)

outputDirectory=$(dirname "$outputFile")
mkdir -p "$outputDirectory"
temporaryFile=$(mktemp "$outputDirectory/.cpu-temperature-XXXXXX")
cat > "$temporaryFile" <<EOF
{
  "title": "CPU & GPU Temperature",
  "symbol": "thermometer.medium",
  "metrics": [
    {
      "title": "CPU",
      "formattedValue": "$formattedCPUTemperature",
      "normalizedValue": $normalizedCPUValue
    },
    {
      "title": "GPU",
      "formattedValue": "$formattedGPUTemperature",
      "normalizedValue": $normalizedGPUValue
    }
  ],
  "lastUpdatedDate": "$lastUpdatedDate"
}
EOF
mv "$temporaryFile" "$outputFile"
