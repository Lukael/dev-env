from __future__ import annotations

import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

from flask import Flask, jsonify, render_template, request

APP_DIR = Path(__file__).resolve().parent
CONFIG_PATH = APP_DIR / "servers.json"

app = Flask(__name__)


def load_config() -> Dict[str, Any]:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def ssh_run(
    host: str, user: str, port: int, ssh_options: List[str], remote_cmd: str
) -> Dict[str, Any]:
    t0 = datetime.now(timezone.utc)
    target = f"{user}@{host}"
    cmd = ["ssh", "-p", str(port), *ssh_options, target, remote_cmd]

    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=12,
            check=False,
        )
        if p.returncode != 0:
            return {
                "ok": False,
                "host": host,
                "error": (p.stderr or p.stdout or "").strip()[:800],
                "data": [],
                "elapsed_ms": int(
                    (datetime.now(timezone.utc) - t0).total_seconds() * 1000
                ),
            }

        out = (p.stdout or "").strip()
        data = json.loads(out) if out else []
        if not isinstance(data, list):
            data = []
        return {
            "ok": True,
            "host": host,
            "error": "",
            "data": data,
            "elapsed_ms": int((datetime.now(timezone.utc) - t0).total_seconds() * 1000),
        }

    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "host": host,
            "error": "SSH timeout",
            "data": [],
            "elapsed_ms": int((datetime.now(timezone.utc) - t0).total_seconds() * 1000),
        }
    except json.JSONDecodeError as e:
        return {
            "ok": False,
            "host": host,
            "error": f"JSON parse error: {e}",
            "data": [],
            "elapsed_ms": int((datetime.now(timezone.utc) - t0).total_seconds() * 1000),
        }


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/metrics")
def api_metrics():
    cfg = load_config()
    servers = cfg.get("servers", [])
    ssh_options = cfg.get("ssh_options", [])

    remote_cmd = request.args.get("cmd", "/usr/local/bin/gpu_docker_metrics.sh")

    results: List[Dict[str, Any]] = []
    rows: List[Dict[str, Any]] = []

    with ThreadPoolExecutor(max_workers=min(16, max(1, len(servers)))) as ex:
        futs = []
        for s in servers:
            futs.append(
                ex.submit(
                    ssh_run,
                    s["host"],
                    s.get("user", "ubuntu"),
                    int(s.get("port", 22)),
                    ssh_options,
                    remote_cmd,
                )
            )
        for f in as_completed(futs):
            r = f.result()
            results.append(r)
            if r["ok"]:
                for item in r["data"]:
                    # Normalize fields for dashboard safety
                    item.setdefault("server", r["host"])
                    item.setdefault("gpu_idx", -1)
                    item.setdefault("container", "unknown")
                    item.setdefault("container_user", "root")
                    item.setdefault("gpu_util", 0)
                    item.setdefault("vram_mb", 0)
                    item.setdefault("process", "unknown")
                    rows.append(item)

    now = datetime.now(timezone.utc).isoformat()
    return jsonify({"ts_utc": now, "servers": results, "rows": rows})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
