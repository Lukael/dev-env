# CPU 및 GPU 온도 샘플

이 샘플은 RunCat Neo의 Custom Metrics 카드에 Apple Silicon CPU 및 GPU 온도를 표시합니다. Metrics Bar 값은 출력하지 않습니다. `runcat-temperature`는 `AppleSMC`의 CPU/GPU 온도 키만 우선 읽고, 접근할 수 없는 장비에서는 Apple Silicon HID 온도 센서를 보조로 사용합니다. CPU 사용률, 전력, 메모리, 프로세스 등 다른 시스템 지표는 읽지 않습니다.

```text
runcat-temperature (상주, 5초 간격) -> monitor-cpu-gpu-temperature.sh -> cpu-temperature.json -> RunCat Neo
```

센서 읽기 프로세스와 LaunchAgent는 계속 실행됩니다. 다만 센서 클라이언트를 한 번 열어 유지하고 5초마다 CPU/GPU 온도 두 값만 읽으므로, `mactop`을 쓰는 것보다 훨씬 작은 작업량입니다. 이 도구는 Apple의 문서화되지 않은 HID 인터페이스를 사용하므로 App Store 앱에 내장하지 않고, 사용자가 컴파일해 쓰는 외부 공급자로만 제공합니다. macOS 또는 새 칩에서 센서 이름이 바뀌면 갱신이 필요할 수 있습니다.

## 설치

1. 이 디렉터리에서 실행 파일을 컴파일합니다. Xcode Command Line Tools가 필요합니다.
   ```bash
   mkdir -p ~/.runcat
   cp runcat-temperature.m ~/.runcat/runcat-temperature.m
   xcrun clang -fobjc-arc -framework Foundation -framework IOKit \
     -o ~/.runcat/runcat-temperature ~/.runcat/runcat-temperature.m
   ~/.runcat/runcat-temperature
   ```
   마지막 명령은 다음처럼 한 줄의 JSON을 출력해야 합니다.
   ```json
   {"cpu_temp":47.3,"gpu_temp":42.8}
   ```
2. 변환 및 모니터 스크립트를 복사하고 실행 권한을 부여합니다.
   ```bash
   cp update-cpu-temperature.sh ~/.runcat/update-cpu-temperature.sh
   cp monitor-cpu-gpu-temperature.sh ~/.runcat/monitor-cpu-gpu-temperature.sh
   chmod +x ~/.runcat/update-cpu-temperature.sh
   chmod +x ~/.runcat/monitor-cpu-gpu-temperature.sh
   ```
3. 한 번 실행해 RunCat용 JSON 파일이 생성되는지 확인합니다.
   ```bash
   ~/.runcat/update-cpu-temperature.sh
   cat ~/.runcat/cpu-temperature.json
   ```
4. 5초마다 값을 갱신하도록 LaunchAgent를 등록합니다.
   ```bash
   cp dev.runcat.cpu-temperature-sample.plist \
     ~/Library/LaunchAgents/dev.runcat.cpu-temperature-sample.plist
   ```
   복사한 plist를 열어 `/Users/YOU`를 홈 디렉터리 경로로 바꾼 뒤 다음을 실행합니다.
   ```bash
   launchctl bootstrap gui/$(id -u) \
     ~/Library/LaunchAgents/dev.runcat.cpu-temperature-sample.plist
   ```
5. RunCat Neo에서 **Settings -> Metrics -> Custom Metrics**를 열고 **Add JSON Source**를 클릭한 다음 `~/.runcat/cpu-temperature.json`을 선택합니다. 이 폴더는 열기 패널에서 숨겨져 있으므로 `Cmd+Shift+.` 또는 `Cmd+Shift+G`로 경로를 입력합니다.
6. Metrics Bar에서 이 소스의 토글은 끈 상태로 둡니다. 이 샘플은 메뉴 막대 텍스트를 출력하지 않고 카드만 갱신합니다.

갱신을 중지하려면 에이전트를 해제합니다.

```bash
launchctl bootout gui/$(id -u)/dev.runcat.cpu-temperature-sample
```

## 동작과 설정

`runcat-temperature --interval 5`는 프로세스 하나를 유지한 채 5초마다 다음 JSON 한 줄만 출력합니다. 모니터 스크립트가 이를 RunCat Custom Metrics 형식으로 바꿔 `~/.runcat/cpu-temperature.json`에 원자적으로 씁니다. 프로세스가 종료되면 LaunchAgent의 `KeepAlive`가 다시 시작합니다.

`RUNCAT_OUT_FILE`로 JSON 출력 경로를 바꿀 수 있습니다. `RUNCAT_CPU_TEMPERATURE_COMMAND`로 컴파일한 실행 파일 경로를 바꿀 수 있습니다. 한 번만 읽으려면 `runcat-temperature`를 인수 없이 실행하고, 수집 주기를 바꾸려면 모니터 스크립트의 `--interval 5` 값을 정수 초 단위로 조정합니다.

각 `normalizedValue`는 `temperature / 100`을 `0...1` 범위로 제한한 값입니다. 그래서 대시보드의 기본 진행 막대는 온도가 100°C에 얼마나 가까운지를 나타냅니다.

## 문제 해결

- `xcrun: error` -> `xcode-select --install`로 Xcode Command Line Tools를 설치합니다.
- `Unable to open AppleSMC or Apple Silicon HID temperature sensors` -> 이 소스의 최신 버전을 다시 복사해 컴파일합니다. 두 인터페이스가 모두 macOS에서 거부된 경우에는 이 외부 도구로 온도를 읽을 수 없습니다.
- `Unable to find separate valid CPU and GPU temperature sensors` -> `AppleSMC` 또는 HID에 CPU/GPU를 구분하는 온도 키가 노출되지 않은 장비입니다. `~/.runcat/runcat-temperature`를 Terminal에서 직접 실행해 같은 오류가 반복되는지 확인합니다.
- 카드에 **missing**이 표시됨 -> `~/.runcat/update-cpu-temperature.sh`를 직접 실행하고 `~/.runcat/cpu-temperature.json`이 올바른 JSON인지 확인합니다.
- 값이 갱신되지 않음 -> `launchctl print gui/$(id -u)/dev.runcat.cpu-temperature-sample`로 에이전트 상태를 확인하고, 복사한 plist의 `/Users/YOU` 경로를 확인합니다.

## 라이선스

Apple Silicon HID 센서 식별 방식은 [MacMonitor](https://github.com/CrackedPixel/MacMonitor)의 `IOReportWrapper.m`을 바탕으로 했으며 MIT License를 따릅니다. `AppleSMC` 접근 방식은 [mactop](https://github.com/metaspartan/mactop)을 바탕으로 했습니다. 각 전문은 [LICENSE-MacMonitor.txt](LICENSE-MacMonitor.txt) 및 [LICENSE-mactop.txt](LICENSE-mactop.txt)에 포함되어 있습니다.
