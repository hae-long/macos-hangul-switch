# Contributing

버그 제보와 macOS·키보드·Moonlight 환경별 검증을 환영합니다.

## 개발 환경

- macOS
- Apple 기본 `/bin/bash`, `plutil`, `hidutil`
- GNU 전용 Bash 기능이나 별도 패키지 없이 동작해야 함

## 변경 절차

1. 사용자에게 보이는 동작을 재현하는 테스트를 먼저 추가합니다.
2. 테스트가 의도한 이유로 실패하는지 확인합니다.
3. 최소한의 구현으로 테스트를 통과시킵니다.
4. 전체 검증을 실행합니다.

```bash
make verify
```

테스트는 임시 홈과 가짜 `hidutil`·`launchctl` 어댑터를 사용합니다. 개발자의 실제 키보드, 입력 소스 또는 Sunshine 설정을 변경해서는 안 됩니다.

## 이슈에 포함할 정보

- `sw_vers` 결과
- Intel 또는 Apple Silicon
- 키보드 모델과 USB·Bluetooth 연결 방식
- 눌렀던 키: 전용 한/영, 오른쪽 Alt, 오른쪽 Command, Caps Lock
- 로컬 또는 Moonlight 원격 여부
- Moonlight 클라이언트 OS와 Sunshine 버전
- `./status.sh` 출력
- 예상 동작과 실제 동작

Sunshine의 `sunshine_state.json`, 인증서, 비밀번호, 토큰, 공인 IP 또는 사용자 홈 전체 경로는 첨부하지 마십시오.

## Pull request

- 하나의 PR에는 하나의 문제나 기능만 포함해 주십시오.
- Bash 3.2 호환성을 유지하십시오.
- 기존 설정을 덮어쓰는 변경에는 충돌·원복 테스트가 필요합니다.
- Caps Lock 또는 Chromium 조합 문제를 해결했다고 표시하려면 물리 키보드와 Moonlight 실사용 재현 절차를 함께 제공해 주십시오.
