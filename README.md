# dev-env

개인 개발 환경을 빠르게 재현하고, GPU 서버 기반 원격 개발 환경을 운영하기 위한 설정/문서 모음입니다. macOS 초기 세팅, 터미널 편의 설정, Coder 기반 Docker 개발 템플릿, GPU 모니터링/유휴 프로세스 알림, Spec-Driven Development 참고 문서를 한 리포지토리에 정리합니다.

## 주요 구성

| 경로 | 설명 |
| --- | --- |
| [`initial/`](./initial) | 새 macOS 개발 장비에서 사용할 기본 설정 파일입니다. Homebrew 번들, Zsh, Vim 설정을 포함합니다. |
| [`server/`](./server) | Ubuntu GPU 서버에 Docker, Coder, GPU 모니터링, 재부팅 알림 등을 설치하기 위한 문서와 스크립트입니다. |
| [`server/templates/`](./server/templates) | Coder 워크스페이스용 Dockerfile/Terraform 템플릿입니다. Ubuntu CUDA 환경과 MATLAB 환경을 제공합니다. |
| [`server/gpu-monitoring/`](./server/gpu-monitoring) | GPU 사용 현황 대시보드와 유휴 GPU 프로세스 감지/알림 스크립트입니다. |
| [`server/reboot-notify/`](./server/reboot-notify) | 서버 재부팅 시 Slack으로 알림을 보내는 systemd 서비스 예시입니다. |
| [`spec-kit/`](./spec-kit) | GitHub Spec Kit 기반 Spec-Driven Development 사용 가이드와 constitution 문서입니다. |
| [`claude/`](./claude) | Claude Code 사용 권한, 모델, 플러그인, 언어 설정 예시입니다. |

## 빠른 시작

### 1. macOS 개발 장비 초기 세팅

`initial/brewfile`에는 자주 사용하는 CLI 도구와 앱이 정리되어 있습니다.

```bash
cd initial
brew bundle --file=brewfile
```

설치 항목 예시:

- CLI/개발 도구: `git`, `mas`, `coder`, `lazygit`, `python@3.12`, `pipenv`
- 터미널/에디터: iTerm2, Visual Studio Code, PyCharm
- 생산성 앱: Slack, Notion, Google Drive, Maccy, BetterTouchTool
- Mac App Store 앱: Xcode, KakaoTalk, RunCat, UpNote, Hidden Bar

필요하면 `initial/.zshrc`, `initial/.vimrc`를 홈 디렉터리에 복사해 사용할 수 있습니다.

```bash
cp initial/.zshrc ~/.zshrc
cp initial/.vimrc ~/.vimrc
```

> 기존 설정이 있다면 덮어쓰기 전에 백업하세요.

### 2. GPU 서버/Coder 환경 구성

상세 절차는 [`server/README.md`](./server/README.md)를 참고하세요. 전체 흐름은 다음과 같습니다.

1. Ubuntu 20.04 이상 서버 준비
2. NVIDIA Driver 설치
3. Docker 및 Docker Compose 설치
4. 필요 시 Docker 데이터 저장 경로 변경
5. Coder를 Docker Compose로 실행
6. `server/templates/Ubuntu` 또는 `server/templates/Matlab` 템플릿을 Coder에 등록
7. 서버별 GPU 개수, Docker host, 마운트 경로 등 Terraform 값을 환경에 맞게 수정

### 3. Coder 워크스페이스 템플릿

#### Ubuntu CUDA 템플릿

[`server/templates/Ubuntu`](./server/templates/Ubuntu)는 NVIDIA CUDA 기반 Ubuntu 개발 컨테이너입니다.

주요 포함 항목:

- `nvidia/cuda:*cudnn-devel-ubuntu*` 기반 이미지
- Python, pipx, Poetry
- Git, tmux, byobu, zsh, vim, lazygit
- Oh My Zsh, zsh 플러그인, Powerlevel10k
- Coder Terraform 리소스와 Docker volume mount 설정

#### MATLAB 템플릿

[`server/templates/Matlab`](./server/templates/Matlab)은 MathWorks MATLAB Docker 이미지를 기반으로 여러 MATLAB Toolbox를 설치하는 Coder 템플릿입니다.

주요 포함 항목:

- MATLAB 릴리스 파라미터
- MATLAB Package Manager 기반 Toolbox 설치
- GPU 서버 선택 파라미터
- 사용자 데이터, 공유 데이터, `/mnt` 마운트 설정

### 4. GPU 모니터링과 알림

[`server/gpu-monitoring`](./server/gpu-monitoring)은 두 가지 기능을 제공합니다.

- [`gpu-dashboard`](./server/gpu-monitoring/gpu-dashboard): 여러 GPU 서버에 SSH로 접속해 Docker/GPU 사용량을 수집하고 Flask API로 제공합니다.
- [`idle-check`](./server/gpu-monitoring/idle-check): `nvidia-smi pmon` 결과를 바탕으로 유휴 GPU 프로세스를 감지하고 Slack 알림 후 종료할 수 있습니다.

각 도구의 설치 방법은 하위 README를 참고하세요.

```bash
# GPU 메트릭 수집 스크립트 단독 확인 예시
cd server/gpu-monitoring/gpu-dashboard
./docker_metrics.sh | jq '.[0]'
```

### 5. 서버 재부팅 알림

[`server/reboot-notify`](./server/reboot-notify)는 서버가 재부팅되었을 때 Slack으로 호스트명, IP, 부팅 시각, 업타임, 직전 로그 등을 보내는 예시입니다.

사용 전 다음 값을 반드시 환경에 맞게 채워야 합니다.

- `SLACK_BOT_TOKEN`
- `SLACK_CHANNEL_ID`

설치 예시는 [`server/reboot-notify/README.md`](./server/reboot-notify/README.md)를 참고하세요.

### 6. Spec Kit 문서

[`spec-kit/README.md`](./spec-kit/README.md)는 GitHub Spec Kit을 이용한 Spec-Driven Development 흐름을 정리합니다.

권장 순서:

1. `specify init`
2. `/speckit.constitution`
3. `/speckit.specify`
4. `/speckit.plan`
5. `/speckit.tasks`
6. `/speckit.implement`

## 보안/개인 설정 주의사항

이 리포지토리에는 개인 개발 환경과 서버 운영 스크립트가 포함되어 있으므로 다음 사항을 주의하세요.

- Slack Bot Token, Channel ID, SSH host, 서버 주소, 사용자별 경로 등 민감한 값은 커밋하지 마세요.
- `server/gpu-monitoring/*/README.md`와 스크립트의 토큰/채널 placeholder를 실제 운영 환경에 맞게 별도 관리하세요.
- Coder Terraform 템플릿의 Docker host, GPU 개수, 마운트 경로는 서버 구성에 맞게 수정해야 합니다.
- `initial/.zshrc`를 그대로 적용하면 기존 shell 설정을 덮어쓸 수 있으므로 백업 후 적용하세요.

## 참고 문서

- [server/README.md](./server/README.md): Docker/Coder/GPU 서버 구성 상세 가이드
- [server/gpu-monitoring/gpu-dashboard/README.md](./server/gpu-monitoring/gpu-dashboard/README.md): GPU 대시보드 설치
- [server/gpu-monitoring/idle-check/README.md](./server/gpu-monitoring/idle-check/README.md): 유휴 GPU 프로세스 감지 서비스
- [server/reboot-notify/README.md](./server/reboot-notify/README.md): 재부팅 Slack 알림 서비스
- [spec-kit/README.md](./spec-kit/README.md): Spec Kit 사용 방법
