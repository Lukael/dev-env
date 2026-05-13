# Installation

1. Setup
```bash
sudo chmod +x docker_metrics.sh
sudo cp docker_metrics.sh /usr/local/bin/docker_metrics.sh
```

2. Python Setup
```bash
pip install flask
pip install gunicorn
```
```bash
sudo cp gpu-dashboard.service /etc/systemd/system
sudo mkdir -p /opt/gpu-dashboard
sudo rsync -av gpu-dashboard/ /opt/gpu-dashboard/
sudo systemctl daemon-reload
sudo systemctl enable --now gpu-dashboard
```


0. Debug
```bash
./docker_metrics.sh | jq '.[0]'
```

## Slow SSH links

The dashboard refresh endpoint returns cached data immediately while a background
poller refreshes SSH metrics. Tune these values in `servers.json` when remote
links are slow:

- `poll_interval_seconds`: how often the background poller starts a refresh.
- `ssh_command_timeout_seconds`: max time allowed for one SSH metrics command.
- `stale_after_seconds`: when the last successful rows are marked as stale.
- `ssh_options`: includes `-C` to compress SSH output on slow links.

If an SSH refresh times out after a previous success, the web UI keeps showing
the last successful process rows and marks that server as `stale cache` instead
of dropping it from the page.

The provided systemd unit runs one gunicorn worker so the in-memory background
cache has a single owner. If you raise the worker count, move the cache to a
shared store first.
