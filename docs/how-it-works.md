# 동작 원리

## 입력 경로

물리 키보드와 Moonlight 입력은 서로 다른 지점에서 F18로 합쳐집니다.

```text
물리 키보드
  LANG1 0x90 / Right Alt 0xE6 / 선택적 Right Command 0xE7
    → macOS hidutil
    → F18 HID usage 0x6D
    → macOS key code 79
    → “이전 입력 소스 선택”

Windows Moonlight
  Han/Yeong 또는 Right Alt
    → VK_RMENU 0xA5
    → Sunshine keybindings
    → VK_F18 0x81
    → macOS key code 79
    → “이전 입력 소스 선택”
```

macOS 입력 소스 단축키 60의 매개변수는 다음과 같습니다.

```text
[65535, 79, 8388608]
```

여기서 79는 macOS F18 키 코드입니다. ABC와 두벌식처럼 주로 두 입력 소스를 사용하는 환경에서 Windows의 한/영 키와 유사한 전환을 제공합니다. 입력 소스가 여러 개라면 “이전 입력 소스”의 macOS 동작을 그대로 따릅니다.

## 왜 LaunchAgent가 필요한가

Apple의 `hidutil` 매핑은 영구 설정이 아닙니다. 재시동하거나 마지막 키보드 서비스가 사라지면 매핑이 해제될 수 있습니다. 이 저장소의 사용자 LaunchAgent는 로그인할 때 한 번 실행되고 이후 10초마다 같은 병합 매핑을 재적용합니다.

대상 파일:

```text
~/Library/LaunchAgents/com.local.global-hangul-switch.plist
```

사용자 영역에서 실행되므로 관리자 권한은 필요하지 않지만, FileVault 로그인 화면처럼 사용자 로그인 전에는 적용되지 않습니다.

## 기존 설정을 보존하는 방식

설치 프로그램은 현재 `hidutil property --get UserKeyMapping` 결과를 읽고 숫자형 plist로 정규화한 뒤 프로젝트 매핑을 추가합니다.

- 원본 키가 없으면 새 매핑을 추가합니다.
- 같은 원본 키가 이미 F18로 연결되어 있으면 중복하지 않습니다.
- 같은 원본 키가 다른 목적지에 연결되어 있으면 충돌로 중단합니다.

첫 설치 시 다음 상태를 기록합니다.

```text
~/Library/Application Support/macos-hangul-switch/
```

기록 대상은 기존 LaunchAgent, 기존 HID 매핑, 기존 단축키 60입니다. 재설치는 이 최초 백업을 덮어쓰지 않습니다.

제거할 때 현재 값이 설치 직후 값과 다르다면 사용자가 나중에 변경한 것으로 보고 강제로 덮어쓰지 않습니다. 정상적으로 복원한 상태 디렉터리도 즉시 삭제하지 않고 `.uninstalled-*` 이름으로 보관합니다.

## Sunshine 설정 병합

Sunshine의 macOS 기본 설정 경로는 `~/.config/sunshine`입니다. `keybindings`는 원본·목적지 쌍을 짝수 개의 값으로 받습니다.

프로젝트는 기존 블록을 먼저 전부 파싱한 뒤 다음 쌍만 추가합니다.

```ini
0xA5, 0x81
```

기존 쌍은 유지하고, 홀수 개 값이나 닫히지 않은 블록은 수정하지 않습니다. 오래된 Sunshine 설정 파서에서도 마지막 `]`이 안전하게 처리되도록 파일 끝 줄바꿈을 보장합니다. 변경 전 원본은 `sunshine.conf.backup-macos-hangul-switch-*`로 보관합니다.

Sunshine 재시작은 스트리밍 연결을 끊는 외부 동작이므로 설치 프로그램이 실행하지 않습니다.

## Caps Lock을 포함하지 않은 이유

Caps Lock은 독립적인 macOS 입력 이벤트이며 이 프로젝트의 `hidutil`·Sunshine 매핑 대상이 아닙니다. macOS의 기본 Caps Lock 입력 소스 옵션을 훼손하지 않지만, 검증한 물리·원격 환경에서는 일관된 전환이 확인되지 않았습니다. 가상 HID 드라이버나 별도 이벤트 처리 앱 없이 이 동작까지 강제하지 않습니다.

## 참고 자료

- [Apple TN2450: Remapping Keys in macOS](https://developer.apple.com/library/archive/technotes/tn2450/_index.html)
- [Sunshine configuration: keybindings](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html#keybindings)
- [Microsoft virtual-key codes](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes)
