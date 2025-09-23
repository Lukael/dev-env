# Installation

1. Enter Slack bot token and channel name in [idle_gpu_killer.sh](./idle_gpu_killer.sh)

2. Setup
```bash
chmod +x ./idle_gpu_killer.sh
sudo cp /etc/systemd/system/idle_gpu_killer.service
sudo cp /etc/systemd/system/idle_gpu_killer.timer
```
You also fix the execution time in [idle_gpu_killer.timer](./idle_gpu_killer.timer) (default: 22:00 in KST)

3. Add in system services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now idle_gpu_killer.timer
```

4. Check system service

```bash
sudo systemctl status idle_gpu_killer.timer
sudo systemctl status idle_gpu_killer.service
```
