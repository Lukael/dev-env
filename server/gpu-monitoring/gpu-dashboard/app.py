from __future__ import annotations

import json
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from flask import Flask, jsonify, render_template, request

APP_DIR = Path(__file__).resolve().parent
CONFIG_PATH = APP_DIR / "servers.json"
DEFAULT_REMOTE_CMD = "/usr/local/bin/docker_metrics.sh"
DEFAULT_POLL_INTERVAL_SECONDS = 5.0
DEFAULT_SSH_COMMAND_TIMEOUT_SECONDS = 60.0
DEFAULT_STALE_AFTER_SECONDS = 120.0

app = Flask(__name__)

_cache_lock = threading.Lock()
_cache: Dict[str, Dict[str, Any]] = {}
_refresh_state: Dict[str, Any] = {
    "started": False,
    "running": False,
    "last_started_utc": None,
    "last_finished_utc": None,
    "last_error": "",
}
_stop_event = threading.Event()


def load_config() -> Dict[str, Any]:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def config_float(cfg: Dict[str, Any], key: str, default: float) -> float:
    try:
        value = float(cfg.get(key, default))
    except (TypeError, ValueError):
        return default
    return value if value > 0 else default


def server_key(server: Dict[str, Any]) -> str:
    return f"{server.get('user', 'ubuntu')}@{server['host']}:{int(server.get('port', 22))}"


def server_label(server: Dict[str, Any]) -> str:
    return str(server.get("name") or server["host"])


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ssh_run(
    host: str,
    user: str,
    port: int,
    ssh_options: List[str],
    remote_cmd: str,
    timeout_seconds: float,
    name: Optional[str] = None,
) -> Dict[str, Any]:
    t0 = datetime.now(timezone.utc)
    target = f"{user}@{host}"
    cmd = ["ssh", "-p", str(port), *ssh_options, target, remote_cmd]

    base = {
        "ok": False,
        "host": host,
        "name": name or host,
        "target": target,
        "data": [],
    }

    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
        elapsed_ms = int((datetime.now(timezone.utc) - t0).total_seconds() * 1000)
        if p.returncode != 0:
            return {
                **base,
                "error": (p.stderr or p.stdout or "").strip()[:800],
                "elapsed_ms": elapsed_ms,
            }

        out = (p.stdout or "").strip()
        data = json.loads(out) if out else []
        if not isinstance(data, list):
            data = []
        return {
            **base,
            "ok": True,
            "error": "",
            "data": data,
            "elapsed_ms": elapsed_ms,
        }

    except subprocess.TimeoutExpired:
        return {
            **base,
            "error": f"SSH timeout after {timeout_seconds:g}s",
            "elapsed_ms": int((datetime.now(timezone.utc) - t0).total_seconds() * 1000),
        }
    except json.JSONDecodeError as e:
        return {
            **base,
            "error": f"JSON parse error: {e}",
            "elapsed_ms": int((datetime.now(timezone.utc) - t0).total_seconds() * 1000),
        }


def normalize_rows(result: Dict[str, Any], fallback_server: str) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for item in result.get("data") or []:
        row = dict(item)
        if "server" in row and row["server"] != fallback_server:
            row.setdefault("remote_server", row["server"])
        row["server"] = fallback_server
        row.setdefault("gpu_idx", -1)
        row.setdefault("container", "unknown")
        row.setdefault("container_user", "root")
        row.setdefault("gpu_util", 0)
        row.setdefault("vram_mb", 0)
        row.setdefault("total_vram", 0)
        row.setdefault("used_mem", 0)
        row.setdefault("process", "unknown")
        rows.append(row)
    return rows


def collect_metrics(cfg: Dict[str, Any], remote_cmd: str) -> Dict[str, Any]:
    servers = cfg.get("servers", [])
    ssh_options = cfg.get("ssh_options", [])
    timeout_seconds = config_float(
        cfg, "ssh_command_timeout_seconds", DEFAULT_SSH_COMMAND_TIMEOUT_SECONDS
    )

    results: List[Dict[str, Any]] = []
    rows: List[Dict[str, Any]] = []

    with ThreadPoolExecutor(max_workers=min(16, max(1, len(servers)))) as ex:
        future_to_server = {
            ex.submit(
                ssh_run,
                s["host"],
                s.get("user", "ubuntu"),
                int(s.get("port", 22)),
                ssh_options,
                remote_cmd,
                timeout_seconds,
                server_label(s),
            ): s
            for s in servers
        }
        for future in as_completed(future_to_server):
            server = future_to_server[future]
            result = future.result()
            result["server_key"] = server_key(server)
            results.append(result)
            if result["ok"]:
                rows.extend(normalize_rows(result, server_label(server)))

    return {"servers": results, "rows": rows}


def update_cache_once() -> None:
    cfg = load_config()
    remote_cmd = str(cfg.get("remote_cmd") or DEFAULT_REMOTE_CMD)
    servers_by_key = {server_key(s): s for s in cfg.get("servers", [])}

    with _cache_lock:
        _refresh_state.update(
            {
                "running": True,
                "last_started_utc": utc_now_iso(),
                "last_error": "",
            }
        )

    try:
        snapshot = collect_metrics(cfg, remote_cmd)
        now_mono = time.monotonic()
        now_utc = utc_now_iso()

        with _cache_lock:
            for result in snapshot["servers"]:
                key = result["server_key"]
                server = servers_by_key.get(key, {})
                entry = _cache.setdefault(key, {})
                entry["server"] = server
                entry["last_attempt"] = result
                entry["last_attempt_utc"] = now_utc
                if result.get("ok"):
                    entry["last_success"] = result
                    label = (
                        server_label(server)
                        if server
                        else result.get("name", result["host"])
                    )
                    entry["last_success_rows"] = normalize_rows(
                        result,
                        label,
                    )
                    entry["last_success_monotonic"] = now_mono
                    entry["last_success_utc"] = now_utc
            _refresh_state.update(
                {
                    "running": False,
                    "last_finished_utc": now_utc,
                    "last_error": "",
                }
            )
    except Exception as e:  # Keep the API responsive even if one poll cycle crashes.
        with _cache_lock:
            _refresh_state.update(
                {
                    "running": False,
                    "last_finished_utc": utc_now_iso(),
                    "last_error": str(e),
                }
            )


def poll_loop() -> None:
    while not _stop_event.is_set():
        cfg = load_config()
        poll_interval = config_float(
            cfg, "poll_interval_seconds", DEFAULT_POLL_INTERVAL_SECONDS
        )
        update_cache_once()
        _stop_event.wait(poll_interval)


def ensure_background_poller() -> None:
    with _cache_lock:
        if _refresh_state["started"]:
            return
        _refresh_state["started"] = True
    thread = threading.Thread(target=poll_loop, name="gpu-dashboard-poller", daemon=True)
    thread.start()


def pending_server_result(server: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "ok": False,
        "host": server["host"],
        "name": server_label(server),
        "target": f"{server.get('user', 'ubuntu')}@{server['host']}",
        "server_key": server_key(server),
        "error": "Waiting for first SSH refresh",
        "elapsed_ms": 0,
        "data": [],
        "loading": True,
        "stale": False,
        "cached": False,
        "has_cached_rows": False,
    }


def cached_metrics(cfg: Dict[str, Any]) -> Dict[str, Any]:
    now_mono = time.monotonic()
    now_utc = utc_now_iso()
    stale_after = config_float(cfg, "stale_after_seconds", DEFAULT_STALE_AFTER_SECONDS)

    servers_payload: List[Dict[str, Any]] = []
    rows_payload: List[Dict[str, Any]] = []

    with _cache_lock:
        state = dict(_refresh_state)
        cache_copy = {k: dict(v) for k, v in _cache.items()}

    for server in cfg.get("servers", []):
        key = server_key(server)
        entry = cache_copy.get(key)
        if not entry:
            servers_payload.append(pending_server_result(server))
            continue

        last_success = entry.get("last_success")
        last_attempt = entry.get("last_attempt") or last_success
        success_rows = entry.get("last_success_rows") or []
        age_sec = None
        if entry.get("last_success_monotonic") is not None:
            age_sec = max(0.0, now_mono - float(entry["last_success_monotonic"]))

        has_cached_rows = bool(success_rows)
        serving_stale_rows = bool(
            has_cached_rows
            and (
                age_sec is None
                or age_sec > stale_after
                or not (last_attempt or {}).get("ok", False)
            )
        )

        if last_attempt:
            result = dict(last_attempt)
        else:
            result = pending_server_result(server)
        result.update(
            {
                "server_key": key,
                "cached": has_cached_rows,
                "has_cached_rows": has_cached_rows,
                "stale": serving_stale_rows,
                "last_success_utc": entry.get("last_success_utc"),
                "cache_age_sec": round(age_sec, 1) if age_sec is not None else None,
            }
        )
        servers_payload.append(result)

        for row in success_rows:
            cached_row = dict(row)
            cached_row["stale"] = serving_stale_rows
            cached_row["cache_age_sec"] = result["cache_age_sec"]
            rows_payload.append(cached_row)

    return {
        "ts_utc": now_utc,
        "mode": "cached-background",
        "refresh": state,
        "servers": servers_payload,
        "rows": rows_payload,
    }


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/metrics")
def api_metrics():
    cfg = load_config()
    remote_cmd = request.args.get("cmd")

    # Debug/one-off command requests preserve the old synchronous behavior.
    if remote_cmd:
        snapshot = collect_metrics(cfg, remote_cmd)
        return jsonify({"ts_utc": utc_now_iso(), "mode": "live", **snapshot})

    ensure_background_poller()
    return jsonify(cached_metrics(cfg))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=50000, debug=True)
