#!/bin/bash

# Slack Bot Token (starts with xoxb-)
SLACK_BOT_TOKEN=""

# Target Slack channel ID (e.g., C12345678)
SLACK_CHANNEL_ID=""

# Hostname of the server
HOSTNAME=$(hostname)

# Primary IP address
IP=$(hostname -I | awk '{print $1}')

# Current timestamp
TIME=$(date "+%Y-%m-%d %H:%M:%S")

# Human-readable uptime since boot
UPTIME=$(uptime -p)

# Last reboot record
LAST_REBOOT=$(last -x reboot | head -1 | sed 's/^reboot\s*//')

# Last graceful shutdown record
LAST_SHUTDOWN=$(last -x shutdown | head -1 | sed 's/^shutdown\s*//')

# Last crash record (kernel panic, etc.)
LAST_CRASH=$(last -x crash | head -1 | sed 's/^crash\s*//')

# Determine reboot reason
if [[ -n "$LAST_CRASH" ]]; then
  REASON="⚠️ Crash / Kernel panic"
elif [[ -n "$LAST_SHUTDOWN" ]]; then
  REASON="🛑 Graceful shutdown"
else
  REASON="❓ Power loss / Unknown"
fi

# Collect the last few log lines from the previous boot
PREV_LOG=$(journalctl -b -1 -n 3 --no-pager 2>/dev/null \
           | sed ':a;N;$!ba;s/\n/ | /g')

MESSAGE="🚀 *Server rebooted*
• Host: ${HOSTNAME}
• IP: ${IP}
• Time: ${TIME}
• Uptime: ${UPTIME}
• Reason: ${REASON}
• Last reboot: ${LAST_REBOOT}
• Logs: ${PREV_LOG}"

curl -s -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
  -H "Content-type: application/json" \
  --data "{
    \"channel\": \"${SLACK_CHANNEL_ID}\",
    \"text\": \"${MESSAGE}\"
  }"