from flask import Flask, jsonify, render_template
import subprocess
import docker
import os

app = Flask(__name__)
client = docker.from_env()

def get_gpu_uuid_map():
    """Map GPU UUID to GPU index (e.g., GPU-abc123 → 0)."""
    try:
        output = subprocess.check_output([
            "nvidia-smi",
            "--query-gpu=gpu_uuid,index",
            "--format=csv,noheader,nounits"
        ]).decode().strip().split("\n")
    except:
        return {}

    return {line.split(",")[0].strip(): line.split(",")[1].strip() for line in output}

def get_gpu_process_info():
    try:
        smi_output = subprocess.check_output([
            "nvidia-smi",
            "--query-compute-apps=pid,process_name,gpu_uuid,used_gpu_memory",
            "--format=csv,noheader,nounits"
        ]).decode().strip().split("\n")
    except subprocess.CalledProcessError:
        return []

    uuid_to_index = get_gpu_uuid_map()

    pid_to_container = {}
    for c in client.containers.list():
        try:
            pid = c.attrs['State']['Pid']
            pid_to_container[str(pid)] = c.name
        except:
            continue

    result = []
    for line in smi_output:
        parts = [x.strip() for x in line.split(",")]
        if len(parts) != 4:
            continue

        pid, pname, uuid, mem = parts
        gpu_idx = uuid_to_index.get(uuid, "N/A")
        container = "N/A"

        for cont_pid in pid_to_container:
            if os.path.exists(f"/proc/{pid}/cgroup"):
                with open(f"/proc/{pid}/cgroup") as f:
                    content = f.read()
                    if cont_pid in content:
                        container = pid_to_container[cont_pid]
                        break

        result.append({
            "gpu_index": gpu_idx,
            "container": container,
            "pid": pid,
            "process": pname,
            "gpu": uuid,
            "memory": int(mem)
        })

    return result

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/gpu")
def api():
    return jsonify(get_gpu_process_info())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
