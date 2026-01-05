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