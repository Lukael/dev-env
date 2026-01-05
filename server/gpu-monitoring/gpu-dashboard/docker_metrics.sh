#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# GPU + Docker metrics exporter (JSON) — GPU INDEX output (robust)
#
# Why this version:
#   - Many systems do NOT support: --query-compute-apps=gpu_index
#   - compute-apps reliably provides gpu_uuid
#   - We build a uuid -> index map from --query-gpu, then convert to gpu_idx
#
# Outputs (per GPU process):
#   - server, gpu_idx, pid, user(host), process(host)
#   - vram_mb (per-process), gpu_util (per-GPU index)
#   - container, container_user (Docker Config.User; empty => root)
###############################################################################

HOST="$(hostname)"

# --- Build UUID -> GPU index map ---
GPU_MAP="$(nvidia-smi --query-gpu=index,uuid --format=csv,noheader 2>/dev/null || true)"
declare -A UUID2IDX
while IFS=',' read -r idx uuid; do
  idx="$(echo "$idx" | xargs)"
  uuid="$(echo "$uuid" | xargs)"
  [[ -n "$uuid" ]] && UUID2IDX["$uuid"]="$idx"
done <<< "$GPU_MAP"

# --- GPU utilization per GPU index ---
GPU_UTIL="$(nvidia-smi --query-gpu=index,utilization.gpu --format=csv,noheader,nounits 2>/dev/null || true)"
declare -A UTIL
while IFS=',' read -r idx util; do
  idx="$(echo "$idx" | xargs)"
  util="$(echo "$util" | xargs)"
  [[ -n "$idx" ]] && UTIL["$idx"]="$util"
done <<< "$GPU_UTIL"

GPU_MEM="$(nvidia-smi --query-gpu=index,memory.total,memory.used --format=csv,noheader,nounits 2>/dev/null || true)"
declare -A MEM_TOTAL
declare -A MEM_USED
while IFS=',' read -r idx total used; do
   idx="$(echo "$idx" | xargs)"
   total="$(echo "$total" | xargs)"
   used="$(echo "$used" | xargs)"
   [[ -n "$idx" ]] && MEM_TOTAL["$idx"]="$total"
   [[ -n "$idx" ]] && MEM_USED["$idx"]="$used"
done <<< "$GPU_MEM"

# --- GPU compute processes (gpu_uuid,pid,used_memory) ---
GPU_PROCS="$(nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv,noheader,nounits 2>/dev/null || true)"

# --- Cache: container init PID -> (container name, container user) ---
CONTAINERS="$(docker ps -q 2>/dev/null || true)"
declare -A PID2CNAME
declare -A PID2CUSER

if [[ -n "$CONTAINERS" ]]; then
  while read -r cid; do
    [[ -z "$cid" ]] && continue
    line="$(docker inspect --format '{{.State.Pid}} {{.Name}} {{.Config.User}}' "$cid" 2>/dev/null || true)"
    cpid="$(echo "$line" | awk '{print $1}' | xargs)"
    cname="$(echo "$line" | awk '{print $2}' | xargs)"
    cuser="$(echo "$line" | awk '{print $3}' | xargs)"
    [[ -z "$cpid" || "$cpid" == "0" ]] && continue
    [[ -z "$cuser" ]] && cuser="root"
    PID2CNAME["$cpid"]="${cname#/}"
    PID2CUSER["$cpid"]="$cuser"
  done <<< "$CONTAINERS"
fi

# Helper: walk PPID chain → container init PID
container=""
container_user=""
find_container_for_pid() {
  local pid="$1"
  local limit=30
  container=""
  container_user=""

  while [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 && "$limit" -gt 0 ]]; do
    if [[ -n "${PID2CNAME[$pid]:-}" ]]; then
      container="${PID2CNAME[$pid]}"
      container_user="${PID2CUSER[$pid]:-root}"
      return 0
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | xargs || true)"
    [[ -z "$pid" ]] && break
    limit=$((limit-1))
  done
  return 0
}

# --- Emit JSON array ---

declare -A HAS_PROC

echo "["
first=1

while IFS=',' read -r gpu_uuid pid vram; do
  gpu_uuid="$(echo "$gpu_uuid" | xargs)"
  pid="$(echo "$pid" | xargs)"
  vram="$(echo "$vram" | xargs)"

  [[ -z "$pid" || "$pid" == "0" ]] && continue
  [[ ! "$pid" =~ ^[0-9]+$ ]] && continue

  # Convert UUID -> index
  gpu_idx="${UUID2IDX[$gpu_uuid]:-}"
  [[ -z "$gpu_idx" ]] && gpu_idx=-1

  HAS_PROC["$gpu_idx"]=1

  mem_total="${MEM_TOTAL[$gpu_idx]:-0}"
  mem_used="${MEM_USED[$gpu_idx]:-0}"

  util="${UTIL[$gpu_idx]:-0}"
  [[ -z "$util" || "$util" == "-" ]] && util=0

  find_container_for_pid "$pid"
  [[ -z "$container" ]] && container="unknown"
  [[ -z "$container_user" ]] && container_user="root"

  pname="$(ps -p "$pid" -o comm= 2>/dev/null | xargs || true)"
  [[ -z "$pname" ]] && pname="unknown"
  user="$(ps -p "$pid" -o user= 2>/dev/null | xargs || true)"
  [[ -z "$user" ]] && user="unknown"

  [[ $first -eq 0 ]] && echo ","
  first=0

  cat <<EOF
  {
    "server": "$HOST",
    "gpu_idx": $gpu_idx,
    "pid": $pid,
    "process": "$pname",
    "total_vram": "$mem_total",
    "used_mem": "$mem_used",
    "vram_mb": $vram,
    "gpu_util": $util,
    "container": "$container",
    "container_user": "$container_user",
    "idle": false
  }
EOF
done <<< "$GPU_PROCS"

ALL_GPU_IDX="$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null || true)"

while read -r idx; do
  idx="$(echo "$idx" | xargs)"
  [[ -z "$idx" ]] && continue

  # If this GPU had no compute process row, emit an idle row
  if [[ -z "${HAS_PROC[$idx]:-}" ]]; then
    util="${UTIL[$idx]:-0}"
    [[ -z "$util" || "$util" == "-" ]] && util=0

    [[ $first -eq 0 ]] && echo ","
    first=0

    cat <<EOF
  {
    "server": "$HOST",
    "gpu_idx": $idx,
    "pid": 0,
    "user": "",
    "process": "",
    "vram_mb": 0,
    "gpu_util": $util,
    "container": "(idle)",
    "container_user": "",
    "idle": true
  }
EOF
  fi
done <<< "$ALL_GPU_IDX"

echo "]"