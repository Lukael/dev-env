# Installation

```
chmod +x ./idle_gpu_killer.sh
sudo cp /etc/systemd/system/idle_gpu_killer.service
sudo cp /etc/systemd/system/idle_gpu_killer.timer
```

```
sudo systemctl daemon-reload
sudo systemctl enable --now idle_gpu_killer.timer
```

```
sudo systemctl status idle_gpu_killer.timer
sudo systemctl status idle_gpu_killer.service
```
