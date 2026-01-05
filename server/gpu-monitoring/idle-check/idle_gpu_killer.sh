#!/bin/bash

# ==== Settings ====
SLACK_TOKEN=""  		 	      # Slack Bot User OAuth Token (You can get it from Slack API)
CHANNEL=""                  # Slack channel name (without #)

GPU_UTIL_THRESHOLD=5    # GPU Usage(SM) Threshold
CHECK_INTERVAL=60       # Check interval (s)
REPEAT_COUNT=3

declare -A idle_count   # key = "${gpu}_${pid}" (Idle counter per GPU)
declare -A last_fb

# Linux user name → Slack User ID mapping
declare -A slack_user_map
slack_user_map["lukael"]="U12345678"

send_slack_message() {
  local text="$1"
  response=$(curl -s -X POST \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-type: application/json" \
    --data "{\"channel\":\"$CHANNEL\",\"text\":\"$text\"}" \
    https://slack.com/api/chat.postMessage)

  if echo "$response" | grep -q '"ok":true'; then
    echo "[INFO] Slack message sent."
  else
    echo "[ERROR] Slack API response: $response"
  fi
}

for i in $(seq 1 $REPEAT_COUNT); do
  now_fmt=$(TZ=Asia/Seoul date +"%Y-%m-%d %H:%M:%S")

  pmon_output=$(nvidia-smi pmon -c 1 -s um | tail -n +3 | \
                awk '{printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10}')

  while IFS=, read -r gpu pid type sm mem enc dec jpg ofa fb; do
    [[ -z "$pid" || "$pid" == "-" || "$pid" == "0" ]] && continue

    [[ "$sm"  == "-" ]] && sm=0
    [[ "$fb"  == "-" ]] && fb=0
    pname=$(ps -p "$pid" -o comm= 2>/dev/null); [[ -z "$pname" ]] && pname="unknown"
    user=$(ps -o user= -p "$pid" 2>/dev/null);  [[ -z "$user"  ]] && user="unknown"
    echo "[TOTAL] $now_fmt GPU=$gpu PID=$pid USER=$user NAME=$pname SM=${sm}% FB=${fb}MiB"
    if [[ "$sm" -lt $GPU_UTIL_THRESHOLD && "$fb" -gt 0 ]]; then
      key="${gpu}_${pid}"
      idle_count[$key]=$(( ${idle_count[$key]:-0} + 1 ))
      last_fb[$key]=$fb
      echo "[DEBUG] $now_fmt GPU=$gpu PID=$pid USER=$user NAME=$pname SM=${sm}% FB=${fb}MiB idle_count=${idle_count[$key]}"
    fi
  done <<< "$pmon_output"

  if [[ $i -lt $REPEAT_COUNT ]]; then
    sleep "$CHECK_INTERVAL"
  fi
done

# 최종 판정
for key in "${!idle_count[@]}"; do
  if [[ "${idle_count[$key]}" -ge $REPEAT_COUNT ]]; then
    gpu="${key%%_*}"
    pid="${key#*_}"
    pname=$(ps -p "$pid" -o comm= 2>/dev/null); [[ -z "$pname" ]] && pname="unknown"
    user=$(ps -o user= -p "$pid" 2>/dev/null);  [[ -z "$user"  ]] && user="unknown"
    fb_val=${last_fb[$key]:-0}

    MSG="[$(TZ=Asia/Seoul date +"%Y-%m-%d %H:%M:%S")] 🚨 Idle GPU Process in Server: USER=$user (PID=$pid NAME=$pname GPU=$gpu VRAM=${fb_val}MiB)"
    echo "[INFO] $MSG"
    send_slack_message "$MSG"
    kill -9 $pid
  fi
done
