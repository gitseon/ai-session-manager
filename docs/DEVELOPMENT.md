# 개발 인수인계 (이어서 작업하기)

이 문서는 새 세션이나 다른 PC에서 개발을 이어갈 때 먼저 읽는 문서다. 실제 세션 데이터·비밀번호·개인 경로는 적지 않는다.

## 현재 상태 (v0.1.0)

- 브랜치: `dev/v0.1.0` → `main` PR #1. CI(Windows PowerShell 7, Windows PowerShell 5.1, Linux)에서 Pester 5 전부 통과.
- 구현 완료: 암호화, Claude/Codex 세션 탐색, 선별 백업, 푸시와 원격 blob 검증, 비파괴 복원, 구조 검증, 인수인계 문서, `asm` CLI, 설치 스크립트, 스킬 초안, 문서.
- 아직 안 한 것은 아래 "다음 할 일" 참고.

## 구조

| 위치 | 역할 |
|---|---|
| `bin/asm.ps1`, `asm.cmd` | CLI 진입점. 인자를 명령 함수에 넘기고 출력만 담당 |
| `src/AiSessionManager/Private` | `Crypto`(암호), `Providers`(Claude/Codex 탐색), `Scan`(금지 파일·비밀값), `Repo`(manifest·Git 검증), `Handoff`, `Common` |
| `src/AiSessionManager/Public` | `Backup`, `Restore`, `Doctor`, `Info`(list·status·version·init·handoff) |
| `skills/ai-session-manager/SKILL.md` | 엔진을 호출하는 안내문. 엔진 로직을 넣지 않는다 |
| `tests/` | Pester 5. `Helpers.ps1`이 가짜 세션을 만든다 |
| `scripts/ci.ps1` | CI용 Pester 설치·실행 |

엔진(`src`)과 스킬(`skills`)은 분리한다. 스킬은 `asm` 명령만 호출한다.

## 설계 결정과 이유

- **AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC)**: Windows PowerShell 5.1(.NET Framework)에 AES-GCM이 없다. 키는 PBKDF2-SHA256(기본 20만 회)으로 매번 유도하고 저장하지 않는다.
- **패키지 포맷**: JSON에 파일 바이트를 넣지 않는다. 5.1의 `ConvertFrom-Json`이 큰 문자열(약 2MB)에서 실패하기 때문이다. 메타 JSON + 파일 바이트 연속을 gzip한 뒤 암호화한다.
- **쓰기는 항상 옵트인**: `backup`/`restore`는 기본이 계획 출력이고, `-Apply`/`-Push`가 있어야 쓴다. 푸시는 확인(`yes` 또는 `-Yes`)도 필요하다.
- **복원은 비파괴**: 같은 내용은 건너뛰고 다른 내용은 충돌로 멈춘다. `-Overwrite`는 기존 파일을 `ASM_HOME\restore-backups`로 복사한 뒤 덮어쓴다.
- **원격 검증**: 푸시 후 `git rev-parse origin/<브랜치>:<경로>`와 `git hash-object`의 blob ID를 비교한다(바이너리를 PowerShell 파이프로 옮기지 않기 위함).
- **JSON은 BOM 없음, 사람이 읽는 문서(인수인계)는 BOM 포함 UTF-8**. 모든 `.ps1/.psm1/.psd1`은 BOM 포함(5.1 한글 깨짐 방지, `Compatibility.Tests.ps1`이 검사).

## 알아 둘 함정 (실제로 겪은 것)

1. PowerShell 변수명은 대소문자를 구분하지 않는다. `param($Out)`과 지역 변수 `$out`이 충돌했다.
2. 한글이 바로 뒤따르는 `"$cn개"`는 변수명 `cn개`로 해석된다. `"$($cn)개"`를 쓴다.
3. Windows PowerShell 5.1에서는 git이 stderr로 낸 경고가 `ErrorActionPreference=Stop`일 때 예외가 된다. git 호출은 `Invoke-AsmGit`(엔진) 또는 `Invoke-TestGit`(테스트)로 감싼다. `2>$null`로는 막히지 않는다.
4. `[Text.Encoding]::Latin1`은 .NET Framework에 없다. `GetEncoding(28591)`을 쓴다.
5. GitHub Actions의 `shell:` 키에는 `matrix` 값을 쓸 수 없다. 셸별로 단계를 나눈다.
6. CI 러너에는 전역 git 신원이 없고 `GIT_AUTHOR_*` 환경변수만 있을 수 있다. 신원 점검은 `git var GIT_COMMITTER_IDENT`로 한다.
7. Pester 5의 `TestDrive`는 블록이 끝날 때 그 블록에서 새로 생긴 파일을 지운다. 여러 `Describe`에 걸쳐 쓰는 가짜 원격은 `TestDrive` 밖의 전용 임시 폴더에 둔다.
8. Pester는 5.x로 고정한다(6.x는 시험하지 않음).
9. Windows PowerShell 5.1의 `Get-Content`는 BOM 없는 UTF-8을 ANSI로 읽는다.

## 개발·시험 방법

```powershell
# 로컬 (Pester 5 필요)
Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path ./tests -Output Detailed
```

- 테스트는 가짜 세션만 쓴다. 실제 `~/.claude`, `~/.codex`는 건드리지 않는다.
- 환경변수 `ASM_KDF_ITERATIONS=1000`은 테스트 속도용이다(평소엔 쓰지 않는다).
- 첫 개발 환경(Linux 컨테이너)에서는 Pester를 설치할 수 없어 같은 테스트 파일을 최소 호환 코드로 실행했다. 이 코드는 저장소에 없고, 실제 Pester 동작(예: TestDrive 정리)과 다를 수 있다. 최종 판단은 항상 CI 결과로 한다.

## 검증 상태

| 항목 | 상태 |
|---|---|
| 암호화·변조 거부·비밀값 차단·복원 흐름 | CI 통과 (가짜 데이터) |
| Windows PowerShell 7 / 5.1 / Linux | CI 통과 |
| Claude Code 세션 형식 | 2.1.312(Linux)의 실제 파일로 확인 |
| Claude 세션 Windows 경로 규칙(`C--...`) | **미검증** (규칙 적용만) |
| Codex 실제 세션 형식 | **미검증** (가짜 세션만) |
| `claude --resume` / `codex resume` 실제 재개 | **미검증** |
| GitHub 비공개 저장소로의 실제 푸시, Public 판별 | **미검증** (로컬 bare 저장소로만 시험) |
| 인수인계 문서의 품질 | **미검증** (자동 추출이라 사람이 확인 필요) |

## 다음 할 일 (우선순위 순)

1. **실사용 검증(본인 PC)**: `asm doctor` → `asm list`(Codex 목록과 제목이 나오는지) → 비공개 저장소로 `asm backup -Latest 1 -Push` → 다른 PC/폴더에서 `asm restore -Apply` → 출력된 재개 명령이 실제로 대화를 이어 가는지 확인. 결과로 `docs/FORMATS.md`의 "미검증"을 갱신한다.
2. Codex 형식이 다르면 `Providers.ps1`(`Get-AsmCodexSessions`, `Get-AsmMessage`)을 고친다.
3. Claude 내부 `cwd`와 다른 폴더(`-ProjectPath`)에서 재개할 때의 동작을 확인한다.
4. 스킬: Claude Code·Codex에서 `SKILL.md`가 실제로 로드되는지 확인하고, Codex 쪽 스킬 위치(현재 `~/.codex/skills`는 가정)를 바로잡는다.
5. 보조 데이터(Claude의 `file-history`, `todos`, Codex 설정 등)를 백업 대상에 넣을지 결정한다.
6. VS Code 확장 통합(엔진은 CLI 계약 `asm ... -Json`을 쓰면 된다).
7. 같은 세션을 다시 백업하면 이전 암호문이 Git 이력에 쌓인다. 이력 정리 정책을 정한다.
8. (선택) `actions/checkout`을 Node 24 대응 버전으로 올린다(CI에 Node 20 폐기 경고가 있다).

## 결정이 필요한 것

- 기본 브랜치를 `main`으로 바꾸는 일(저장소 설정). 현재 처음 푸시한 `dev/v0.1.0`이 기본일 수 있다.
- PR #1 병합 시점.
