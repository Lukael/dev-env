# Installation

1. Enter Slack bot token and channel name in [reboot-notify.sh](./reboot-notify.sh)

2. Setup
```bash
chmod +x reboot-notify.sh
sudo cp reboot-notify.sh /usr/local/bin
sudo cp reboot-notify.service /etc/systemd/system
```

3. Add in system services

```bash
sudo systemctl daemon-reload
sudo systemctl enable reboot-notify.sh
```

4. Check system service

```bash
sudo systemctl status idle_gpu_killer.service
```
