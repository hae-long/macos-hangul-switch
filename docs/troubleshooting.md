# 문제 해결과 원복

## 먼저 상태 확인

```bash
./status.sh
```

다음 항목을 각각 표시합니다.

- LaunchAgent 설치 여부
- macOS F18 입력 소스 단축키
- 현재 `LANG1`·오른쪽 Alt HID 매핑
- 선택 기능인 Sunshine `0xA5 → 0x81`

Sunshine을 설치하지 않은 기본 구성에서는 Sunshine 항목이 “not configured” 또는 “configuration unavailable”이어도 전체 물리 키보드 상태는 정상일 수 있습니다.

## 물리 한/영 키가 반응하지 않음

1. 키보드를 연결한 뒤 최대 10초 기다립니다.
2. `./status.sh`를 다시 실행합니다.
3. 현재 HID 매핑을 확인합니다.

```bash
/usr/bin/hidutil property --get UserKeyMapping
```

4. LaunchAgent가 로드되어 있다면 즉시 다시 실행할 수 있습니다.

```bash
launchctl kickstart -k "gui/$(id -u)/com.local.global-hangul-switch"
```

5. macOS 설정 → 키보드 → 키보드 단축키 → 입력 소스에서 “이전 입력 소스 선택”이 F18인지 확인합니다.

사용자 로그인 전 화면에서는 사용자 LaunchAgent가 아직 실행되지 않으므로 동작하지 않습니다.

## 오른쪽 Alt 또는 Command가 원래 기능을 잃음

기본 설치는 오른쪽 Alt를 한/영 전환으로 사용합니다. 전용 `LANG1` 키만 필요한 경우 제거 후 다음 프로필로 다시 설치합니다.

```bash
./uninstall.sh --keep-sunshine
./install.sh --lang1-only
```

오른쪽 Command는 `--right-command`를 사용한 경우에만 프로젝트가 추가합니다.

## 설치가 HID mapping conflict로 중단됨

동일한 원본 키가 이미 F18 이외의 키로 매핑되어 있다는 뜻입니다. 설치 프로그램은 기존 매핑을 덮어쓰지 않습니다.

```bash
/usr/bin/hidutil property --get UserKeyMapping
```

기존 매핑의 목적과 이를 만든 LaunchAgent 또는 스크립트를 확인한 뒤 어느 설정을 유지할지 결정하십시오. 충돌 원인을 모르는 상태에서 `UserKeyMapping` 전체를 빈 값으로 지우는 것은 권장하지 않습니다.

## Moonlight 한/영 키가 반응하지 않음

1. Sunshine 설정 상태를 확인합니다.

```bash
./scripts/sunshine.bash status
```

2. 설정 파일에 `0xA5, 0x81`이 있는지 확인합니다.

```bash
grep -n -A8 -B2 'keybindings' "$HOME/.config/sunshine/sunshine.conf"
```

3. 작업을 저장하고 Sunshine을 재시작합니다. 이 순간 Moonlight 연결이 끊깁니다.

```bash
brew services restart sunshine
```

4. 다시 접속해 한/영 키와 오른쪽 Alt를 각각 시험합니다.

Windows 클라이언트가 한/영 키를 `VK_RMENU(0xA5)`로 보내지 않는 환경은 이 매핑으로 처리되지 않습니다.

## Sunshine 설정 충돌

다음 오류는 `0xA5`가 이미 다른 키로 연결되어 있음을 의미합니다.

```text
Sunshine keybinding conflict: source 0xA5 already maps to another destination
```

파일은 변경되지 않습니다. 기존 매핑의 용도를 확인한 뒤 수동으로 선택해야 합니다. Sunshine 설정을 수정할 때 `keybindings` 값은 반드시 원본·목적지 쌍으로 구성되어야 합니다.

## Caps Lock이 전환되지 않음

Caps Lock은 현재 지원 완료 기능이 아닙니다. 이 프로젝트는 Caps Lock 이벤트를 변경하지 않으므로 macOS의 기본 옵션을 켜 볼 수 있지만, 물리 키보드와 Moonlight 세션 모두에서 일관된 동작을 보장하지 않습니다.

## 한글이 사라졌다가 다시 나타남

일부 Chromium 기반 앱에서 입력 소스를 바꿀 때 조합 중인 한글 marked text가 정상 확정되지 않는 현상입니다.

현재 우회 방법:

1. 한글 입력 후 Space, Enter 또는 방향키로 조합을 확정합니다.
2. 한/영 키를 누릅니다.
3. 영문을 입력합니다.

일반 네이티브 텍스트 입력 앱에서도 같은 현상이 있는지 비교하면 앱 한정 문제인지 판단하는 데 도움이 됩니다.

## 전체 제거

```bash
./uninstall.sh
```

Sunshine 설정은 유지하고 나머지만 제거:

```bash
./uninstall.sh --keep-sunshine
```

제거 뒤에도 복구 상태는 다음 위치에 남습니다.

```text
~/Library/Application Support/macos-hangul-switch.uninstalled-*
```

Sunshine의 개별 변경 전 백업은 원본 설정 옆에 남습니다.

```text
~/.config/sunshine/sunshine.conf.backup-macos-hangul-switch-*
```

문제가 해결되지 않으면 이슈에 macOS 버전, 키보드 연결 방식, `./status.sh` 출력, Moonlight 클라이언트 OS, Sunshine 버전을 첨부해 주십시오. 사용자 이름·IP·인증서·자격 증명은 제거하십시오.
