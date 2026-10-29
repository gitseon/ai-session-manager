---
name: ai-session-manager
description: Claude Code·Codex 세션과 작업 상태를 암호화해 개인 비공개 GitHub 저장소로 백업하고 다른 PC에서 복원한다. "백업해줘", "복원해줘", "백업 상태 확인해줘", "세션 옮겨줘" 같은 요청에 사용한다.
---

# ai-session-manager 스킬

이 스킬은 **얇은 안내 계층**이다. 모든 실제 동작은 `asm` CLI(엔진)가 한다. 직접 파일을 복사하거나 git 명령으로 세션을 옮기지 않는다.

## 요청 → 명령

| 사용자 말 | 실행 |
|---|---|
| 상태 점검 | `asm doctor` |
| 백업 상태 확인 | `asm status` |
| 세션 목록 | `asm list` (백업본: `asm list -Remote`) |
| 백업해줘 | 아래 "백업 절차" |
| 복원해줘 | 아래 "복원 절차" |

## 반드시 지킬 것

1. **쓰기 전에 승인**: `asm backup`/`asm restore`는 `-Apply`/`-Push` 없이 먼저 실행해 **계획**을 보여 주고, 사용자가 대화에서 명시적으로 승인한 뒤에만 `-Apply`(복원) 또는 `-Push -Yes`(백업)를 붙여 다시 실행한다. 승인은 그 한 건에만 유효하다.
2. 비밀번호를 묻거나 출력하지 않는다. 사용자가 터미널에서 직접 입력하거나 `ASM_PASSPHRASE` 환경변수를 스스로 설정해야 한다. 대화형 입력이 불가능한 환경이면 사용자에게 직접 실행하도록 안내한다.
3. 기존 세션 파일을 덮어쓰지 않는다. 충돌이 나면 보고만 하고, `-Overwrite`는 사용자가 따로 승인했을 때만 쓴다.
4. `[주의] 비밀값 의심` 경고가 나온 세션은 `-AllowSecrets`로 우회하지 않고 사용자에게 먼저 알린다.
5. 결과는 `asm` 출력 그대로 보고한다. 실행하지 않은 검증을 했다고 말하지 않는다.

## 백업 절차

1. `asm list`로 후보를 보여 주고 백업할 세션을 사용자와 정한다(`-Session <ID>` 또는 `-Latest N`).
2. `asm backup -Session <ID>` (계획만 출력) → 제외 파일·경고를 요약해 승인 요청.
3. 승인 후 `asm backup -Session <ID> -Push -Yes` → "원격 검증: 일치"까지 확인해 보고.

## 복원 절차

1. 새 PC에서 `asm init -Repo <백업 저장소 클론 경로>` 이후 `asm restore -Session <ID> -Pull` 의 계획 확인(승인 필요: git fetch).
2. `asm restore -Session <ID>` (계획) → 충돌 여부 보고 → 승인 후 `-Apply`.
3. 출력된 **재개 명령**(`claude --resume <ID>` / `codex resume <ID>`)을 사용자에게 안내한다. 실제 재개 성공은 사용자가 CLI에서 확인해야 한다.
4. 재개가 안 되면 `asm restore -Session <ID> -Handoff` 로 인수인계 문서를 만들어 새 세션에 붙여 넣게 한다.
