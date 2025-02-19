# Server Setup

## 0.Prerequisite
* Ubuntu Linux >= 20.04
* Docker
* Docker compose
* Nvidia driver

## 1. Docker 설치

### 1. Docker apt 설정

```bash
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```

### 2. Docker 설치

```bash
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 3. Docker 실행 확인

```bash
sudo docker run hello-world
```

### 4. Docker compose 설치

```bash
sudo apt-get install docker-compose-plugin
```

### 5. Docker compose 실행확인

```bash
docker compose version
```

### 6. Docker 저장 경로 변경(Optional)
coder 사용시에 docker 재부팅시 마다 image를 저장하는 구조라 추후 용량 관리를 위해서는 HDD로 옮기는 게 관리하기 용이할 듯 합니다.

1. 기존 저장 경로 확인

```bash
sudo docker info | grep "Docker Root Dir"
```

2. Docker 서비스 중지

```bash
sudo systemctl stop docker
```

3. 이동할 위치 경로 생성

```bash
sudo mkdir -p {새로운 도커 저장경로}
```

4. Docker 설정 파일 수정

```bash
sudo vim /etc/docker/daemon.json

>>>
{
    "data-root": "새로운 경로"  # ex) "/data/docker"
}
```

5. Docker 재시작

```bash
sudo systemctl start docker
```

## 2. coder 설치
coder를 설치하는 방법은 coder 자체 설치 툴을 이용하는 것이 가장 간단하나 서비스를 간단하게 업데이트 하거나 추후 다른 서비스를 쉽게 올리기위해서 docker compose를 이용하여 설치하는 방법을 알려드립니다.

### 1. Download the docker-compose.yaml file.
```bash
wget https://raw.githubusercontent.com/coder/coder/refs/heads/main/docker-compose.yaml
```

### 2. Update group_add: in docker-compose.yaml with the gid of docker group.
You can get the docker group gid by running the below command:
```bash
getent group docker | cut -d: -f3
```

해당 출력에서 나오는 gid를 다운받은 docker-compose.yaml에 수정하면 됩니다.

```bash
>>>
{
    group_add:
      - "{Your gid number}" # docker group on host
}
```

### 3. Start Coder
docker-compose.yaml이 있는 폴더에서
```bash
docker compose up

or

sudo docker compose up

```

위 커맨드를 실행하게 되면

```bash
View the Web UI:
https://{your-uuid}.try.coder.app
```

위와 같이 link가 나오게 됩니다. 위 링크는 NAT Traversal이 적용된 링크라 외부에서 접근이 가능합니다.

(링크 주소 변경했을 때도 적용되는지는 확인 필요)

### 4. Start Coder in background
```bash
docker compose up -d
```

### 5. Adding Template
1. Create Template
2. Choose a starter template
3. Source Code
4. build/Dockerfile에 repo에 있는 파일로 replace
5. main.tf에 repo에 있는 파일로 replace
6. main.tf에 Line 227 부터 있는 /dev/nvidia*를 현재 GPU에 있는 서버 개수와 동일하게 변경
7. Build & Publish

## 3. GPU Monitoring tool 설치 

아래 Reference 대로 진행해보았는데 GPU docker 쪽 Nvidia-driver issue가 있어서 안되는 듯?

좀 더 develop 필요


## Reference Links
* [Docker installation](https://docs.docker.com/engine/install/ubuntu/)
* [Change Docker image save path](https://dongle94.github.io/docker/docker-image-storage-change/)
* [coder installation](https://coder.com/docs/install/docker)
* [coder docker base](https://github.com/matifali/dockerdl)
* [coder template base](https://github.com/matifali/coder-templates/tree/main)
* [GPU Monitoring](https://github.com/sungreong/gpu-monitoring-in-containers/tree/main)
* [GPU Monitoring 2](https://data-newbie.tistory.com/1005)
* [GPU Monitoring 3](https://github.com/SagiK-Repository/Monitoring?tab=readme-ov-file#docker-grafana-prometeus-%ED%99%9C%EC%9A%A9%ED%95%9C-nvidia-gpu-%EB%AA%A8%EB%8B%88%ED%84%B0%EB%A7%81)
