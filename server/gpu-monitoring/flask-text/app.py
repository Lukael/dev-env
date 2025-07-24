from flask import Flask, render_template_string
import subprocess
import re
import os
from collections import defaultdict

app = Flask(__name__)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="5">
    <title>GPU Monitor</title>
    <style>
        body { font-family: sans-serif; padding: 20px; background: #f5f5f5; }
        h1 { color: #333; }
        .gpu { background: white; padding: 15px; margin-bottom: 20px; border-radius: 8px; box-shadow: 0 0 8px rgba(0,0,0,0.1); }
        .cmd { font-family: monospace; font-size: 0.9em; background: #eee; padding: 5px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>🎯 GPU Usage Dashboard</h1>
    {% for gpu in gpus %}
        <div class="gpu">
            <h2>🖥️ GPU {{ gpu.index }} ({{ gpu.name }}): {{ gpu.used }} / {{ gpu.total }} MiB ({{ gpu.percent }}%), Util: {{ gpu.util }}%</h2>
            {% for proc in gpu.processes %}
                <p>🔹 <b>[{{ proc.container }}]</b> PID {{ proc.pid }} → {{ proc.mem }} MiB<br>
                <span class="cmd">▶ {{ proc.cmd }}</span></p>
            {% endfor %}
        </div>
    {% endfor %}
</body>
</html>
"""

def get_gpu_index_mapping():
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=gpu_uuid,gpu_bus_id,index", "--format=csv,noheader,nounits"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    uuid_to_index, busid_to_index = {}, {}
    for line in result.stdout.strip().split('\n'):
        uuid, busid, idx = [s.strip() for s in line.split(',')]
        uuid_to_index[uuid] = idx
        busid_to_index[busid] = idx
    return uuid_to_index, busid_to_index

def get_gpu_summary():
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=index,name,memory.total,utilization.gpu", "--format=csv,noheader,nounits"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    gpu_info = {}
    for line in result.stdout.strip().split('\n'):
        idx, name, total, util = [s.strip() for s in line.split(',')]
        gpu_info[idx] = {"name": name, "memory_total": int(total), "gpu_util": int(util)}
    return gpu_info

def get_gpu_processes():
    result = subprocess.run(
        ["nvidia-smi", "--query-compute-apps=gpu_uuid,gpu_bus_id,pid,process_name,used_gpu_memory",
         "--format=csv,noheader,nounits"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    processes = []
    for line in result.stdout.strip().split('\n'):
        parts = [s.strip() for s in line.split(',')]
        if len(parts) == 5:
            gpu_uuid, bus_id, pid, proc, mem = parts
            processes.append({
                "GPU_UUID": gpu_uuid, "GPU_BUS": bus_id, "PID": pid,
                "Process": proc, "GPU_MiB": int(mem)
            })
    return processes

def get_container_name_from_pid(pid):
    try:
        host_proc = os.environ.get("HOST_PROC", "/proc")
        with open(f"{host_proc}/{pid}/cgroup") as f:
            content = f.read()
            # 다양한 형태에 대응
            patterns = [
                r"/docker/([0-9a-f]{12,64})",                 # 일반적인 docker cgroup
                r"docker-([0-9a-f]{12,64})\.scope",           # systemd
                r"/\.\./docker-([0-9a-f]{64})\.scope"
            ]
            for pattern in patterns:
                match = re.search(pattern, content)
                if match:
                    container_id = match.group(1)
                    name = subprocess.run(
                        ["docker", "inspect", "--format", "{{.Name}}", container_id],
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
                    )
                    return name.stdout.strip().lstrip("/")
    except Exception as e:
        print(f"[ERROR] Exception while resolving container name for PID {pid}: {e}", flush=True)
        return None
    return None

def get_command_from_pid(pid):
    try:
        result = subprocess.run(["ps", "-p", pid, "-o", "args="],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        return result.stdout.strip()
    except:
        return None

@app.route("/")
def dashboard():
    uuid_to_index, busid_to_index = get_gpu_index_mapping()
    gpu_summary = get_gpu_summary()
    processes = get_gpu_processes()

    usage_by_gpu = defaultdict(list)
    usage_by_gpu_total = defaultdict(int)

    for proc in processes:
        pid = proc["PID"]
        mem = proc["GPU_MiB"]
        gpu_uuid = proc["GPU_UUID"]
        gpu_bus = proc["GPU_BUS"]
        proc_name = proc["Process"]
        cname = get_container_name_from_pid(pid) or "unknown"
        cmdline = get_command_from_pid(pid) or proc_name
        gpu_idx = uuid_to_index.get(gpu_uuid) or busid_to_index.get(gpu_bus) or "unknown"
        usage_by_gpu_total[gpu_idx] += mem
        usage_by_gpu[gpu_idx].append({
            "container": cname, "pid": pid, "mem": mem, "cmd": cmdline
        })

    gpus = []
    for idx in sorted(gpu_summary.keys(), key=lambda x: int(x)):
        total = gpu_summary[idx]["memory_total"]
        used = usage_by_gpu_total.get(idx, 0)
        percent = round((used / total) * 100, 1) if total else 0
        util = gpu_summary[idx]["gpu_util"]
        gpus.append({
            "index": idx,
            "name": gpu_summary[idx]["name"],
            "total": total,
            "used": used,
            "percent": percent,
            "util": util,
            "processes": usage_by_gpu.get(idx, [])
        })

    return render_template_string(HTML_TEMPLATE, gpus=gpus)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
