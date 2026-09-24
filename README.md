# macOS Hangul Switch

[English](README.en.md)

Windows 키보드의 한/영 키를 macOS에서 전역 입력 소스 전환 키로 사용합니다. 물리 키보드와 Windows Moonlight 클라이언트를 지원하며, Karabiner-Elements 같은 추가 키 매핑 앱이나 `sudo`가 필요하지 않습니다.

## 지원 범위

| 기능 | 상태 | 비고 |
|---|---:|---|
| 물리 키보드 `LANG1` 한/영 키 | ✅ | 기본 적용 |
| 물리 키보드 오른쪽 Alt | ✅ | 기본 적용, 원래 Option 기능을 대신함 |
| 물리 키보드 오른쪽 Command | ✅ | `--right-command` 선택 기능 |
| Windows Moonlight 한/영·오른쪽 Alt | ✅ | `--sunshine` 선택 기능 |
| 로그인·재부팅·키보드 재연결 후 복구 | ✅ | 사용자 LaunchAgent가 10초마다 확인 |
| 기존 설정 백업 및 제거 시 복원 | ✅ | 충돌하는 매핑은 덮어쓰지 않음 |
| Caps Lock 한/영 전환 | ⚠️ | 이 프로젝트가 변경하지 않으며 동작을 보장하지 않음 |
| Chromium 계열 앱의 조합 중 글자 문제 | ⚠️ | 앱의 marked-text 처리 문제로 미해결 |

검증 환경은 macOS 26.3.1 Apple Silicon, Sunshine `2026.516.143833`, Windows Moonlight 클라이언트입니다. 다른 macOS·Sunshine 버전은 이슈 제보와 추가 검증을 환영합니다.

## 빠른 설치

macOS에 영어(ABC)와 한국어(두벌식) 입력 소스를 먼저 추가합니다. 이 프로젝트는 입력 소스 자체를 설치하지 않습니다.

터미널에서 저장소를 복제하고 설치합니다. 기본 설치에서는 오른쪽 Alt가 기존 Option 기능 대신 한/영 전환 키로 동작합니다.

```bash
git clone https://github.com/hae-long/macos-hangul-switch.git
cd macos-hangul-switch
./install.sh
./status.sh
```

`./status.sh`로 LaunchAgent, F18 단축키, 키 매핑이 활성 상태인지 확인합니다. 기본 설정은 모든 키보드의 다음 입력을 F18로 변환합니다.

- 전용 한/영 키가 보내는 HID `LANG1`
- 오른쪽 Alt

오른쪽 Alt의 기존 Option 기능을 유지하고 전용 한/영 키만 사용하려면 다음과 같이 설치합니다.

```bash
./install.sh --lang1-only
```

현재 이 저장소를 만들 때 검증한 전체 구성과 동일하게 설치하려면 다음 명령을 사용합니다.

```bash
./install.sh --right-command --sunshine
```

이 구성에서는 오른쪽 Alt와 오른쪽 Command가 원래 modifier 기능 대신 한/영 전환으로 동작합니다.

### 설치 옵션

| 옵션 | 동작 |
|---|---|
| `--lang1-only` | 물리 키보드에서는 전용 `LANG1` 키만 매핑 |
| `--right-command` | 오른쪽 Command도 한/영 전환으로 사용 |
| `--sunshine` | `~/.config/sunshine/sunshine.conf`에 원격용 매핑 추가 |

설치 프로그램은 기존 `hidutil` 매핑을 병합합니다. 같은 원본 키에 다른 목적지가 이미 지정되어 있으면 파일을 변경하지 않고 충돌을 알립니다.

## Moonlight / Sunshine

Windows Moonlight에서 전달되는 한/영 키와 오른쪽 Alt가 macOS 오른쪽 Option으로 들어오는 환경에서는 Sunshine에 다음 변환이 필요합니다.

```text
0xA5 (VK_RMENU) → 0x81 (VK_F18)
```

다음 명령으로 물리 키보드 설정과 함께 추가할 수 있습니다.

```bash
./install.sh --sunshine
```

Sunshine 설정은 백업 후 병합되며, 기존 `0xA5` 매핑이 충돌하면 변경하지 않습니다. 현재 Moonlight 연결을 끊지 않도록 Sunshine은 자동 재시작하지 않습니다.

작업을 저장한 후 Sunshine 설치 방식에 맞게 직접 재시작하십시오. 재시작 순간 Moonlight 연결이 끊어지므로 다시 접속해야 합니다.

Homebrew 서비스 예시:

```bash
brew services restart sunshine
```

또는 현재 사용자 LaunchAgent를 사용하는 경우:

```bash
launchctl kickstart -k "gui/$(id -u)/homebrew.mxcl.sunshine"
```

Sunshine 앱으로 설치했다면 앱을 완전히 종료한 뒤 다시 실행합니다.

사용자 지정 Sunshine 설정 파일은 환경 변수로 지정할 수 있습니다.

```bash
MHS_SUNSHINE_CONFIG=/path/to/sunshine.conf ./install.sh --sunshine
```

## 제거와 복원

```bash
./uninstall.sh
```

다음 항목을 설치 전 상태로 복원합니다.

- 기존 `hidutil` 매핑
- macOS 입력 소스 단축키 60
- 동일 경로에 있던 기존 LaunchAgent
- 이 프로젝트가 직접 추가한 Sunshine `0xA5 → 0x81` 매핑

설치 전부터 Sunshine 매핑이 존재했다면 제거하지 않습니다. Sunshine 설정만 유지하려면 다음 옵션을 사용합니다.

```bash
./uninstall.sh --keep-sunshine
```

복구용 상태는 삭제하지 않고 다음과 같은 이름으로 보관합니다.

```text
~/Library/Application Support/macos-hangul-switch.uninstalled-날짜-시간-PID
```

## 알려진 제한사항

### Caps Lock

이 프로젝트는 Caps Lock을 다른 키로 변환하지 않습니다. macOS의 “Caps Lock 키로 ABC와 마지막으로 사용한 비라틴 입력 소스 간 전환” 설정은 그대로 유지되지만, 실제 검증에서는 물리 키보드와 원격 세션 모두에서 일관되게 작동하지 않았습니다. 따라서 현재 지원 완료 기능으로 표시하지 않습니다.

### Chromium 계열 앱의 한글 조합

Codex 같은 일부 Chromium 기반 앱에서는 조합 중인 한글 직후 입력 소스를 바꾸면 한글이 잠시 사라지고 영문이 덮어쓴 것처럼 보였다가, 다시 한글 입력 소스로 전환할 때 나타나는 현상이 확인되었습니다. 한글 조합을 Space, Enter 또는 방향키로 먼저 확정한 뒤 전환하는 것이 현재의 우회 방법입니다.

### 원격 키 코드 차이

Moonlight 클라이언트, 키보드 레이아웃 또는 운영체제에 따라 한/영 키가 `VK_RMENU(0xA5)`가 아닌 다른 코드로 전달될 수 있습니다. 이 경우 Sunshine 설정만으로 동작하지 않을 수 있습니다.

## 더 알아보기

- [동작 원리](docs/how-it-works.md)
- [문제 해결과 원복](docs/troubleshooting.md)
- [기여 안내](CONTRIBUTING.md)

## 라이선스

[MIT](LICENSE)
