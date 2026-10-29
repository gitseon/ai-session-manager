# ai-session-manager (asm)

Windows에서 **Claude Code**와 **Codex**의 대화 세션을 암호화해 개인 비공개 GitHub 저장소로 백업하고, 다른 PC에서 복원하는 도구입니다.

> 현재 버전: **v0.1.0** (핵심 엔진 + CLI). 공통 AI 스킬 초안(`skills/`)이 들어 있고, VS Code 확장 통합은 아직 없습니다.

## 어떻게 동작하나요? (쉬운 설명)

1. 이 저장소(Public)에는 **프로그램만** 있습니다. 내 대화 내용은 들어 있지 않습니다.
2. 내 대화는 **내가 만든 비공개(Private) 저장소**에 올라갑니다. 올리기 전에 내 비밀번호로 잠급니다(AES-256).
3. 비밀번호는 어디에도 저장되지 않습니다. 잃어버리면 복구할 수 없습니다.
4. 다른 PC에서 같은 비밀번호로 풀면 대화가 원래 자리로 돌아옵니다.

## 빠른 시작

```powershell
# 1) 설치 (PowerShell 7 또는 Windows PowerShell 5.1)
git clone https://github.com/gitseon/ai-session-manager.git
cd ai-session-manager
.\install.ps1 -AddToPath -InstallSkill

# 2) 내 비공개 백업 저장소(GitHub에서 Private으로 미리 생성)를 클론하고 연결
asm init -Clone https://github.com/<내계정>/<비공개저장소>.git -Repo C:\asm-data

# 3) 점검 → 목록 → 백업(계획 확인 후 실행)
asm doctor
asm list
asm backup -Latest 1            # 계획만 출력 (아무것도 쓰지 않음)
asm backup -Latest 1 -Push      # 암호화 + 커밋 + 푸시 + 원격 검증

# 4) 다른 PC에서
asm restore -Session <ID> -Pull          # 계획 출력
asm restore -Session <ID> -Pull -Apply   # 실제 복원
```

자세한 내용: [설치](docs/INSTALL.md) · [사용법](docs/USAGE.md) · [보안 정책](docs/SECURITY.md) · [세션 저장 형식과 검증 상태](docs/FORMATS.md)

## 명령

| 명령 | 설명 |
|---|---|
| `asm doctor` | 환경 점검(PowerShell, git, Claude/Codex, 저장소 공개 여부, 암호화 자체 시험) |
| `asm backup` | 선택한 세션 암호화·업로드. 기본은 **계획만** 출력 |
| `asm restore` | 복호화 후 세션 폴더로 복원. 기본은 **계획만** 출력, 기존 파일은 덮어쓰지 않음 |
| `asm list` | 로컬 세션 목록 (`-Remote`: 백업본) |
| `asm status` | 백업 대비 로컬 변경, 푸시 안 된 커밋 확인 |
| `asm version` | 버전 |
| `asm init` · `asm handoff` | 백업 저장소 연결 · 인수인계 문서 생성 (보조 명령) |

## 안전 원칙

- 쓰기에는 항상 명시 옵션이 필요합니다(`-Apply`, `-Push`). 푸시는 `yes` 확인(또는 `-Yes`)도 필요합니다.
- 인증 토큰·OAuth 캐시·키 파일(`.credentials.json`, `auth.json`, `*.pem` 등)은 **목록에서 제외**하고 업로드하지 않습니다.
- Public 저장소는 푸시를 거부합니다. 강제 푸시·삭제 명령은 없습니다.
- 복원은 기존 파일을 보존합니다. 충돌 시 멈추고, `-Overwrite`일 때만 기존 파일을 `ASM_HOME\restore-backups`에 복사해 두고 덮어씁니다.

## 구조

```
bin/asm.ps1, asm.cmd            CLI 진입점 (엔진 호출만)
src/AiSessionManager/           엔진 모듈 (Private: 암호·공급자·Git / Public: 명령)
skills/ai-session-manager/      AI 스킬 계층 (SKILL.md, 엔진을 호출하는 안내문)
tests/                          Pester 5 테스트
.github/workflows/ci.yml        Windows(PS7, PS5.1) + Linux CI
```

엔진과 스킬은 분리되어 있습니다. 스킬은 `asm` 명령만 호출합니다.

## 한계 (v0.1.0)

- Claude의 `file-history`, `todos` 등 세션 외 보조 데이터와 Codex 설정은 백업하지 않습니다.
- 복원 후 "원래 대화 재개"의 최종 성공 여부는 해당 CLI에서 사람이 확인해야 합니다. 구조 검증만 자동입니다.
- 재개가 불가능하면 `asm restore -Handoff`로 작업 인수인계 문서를 만들어 새 세션에 붙여 넣습니다.

## 라이선스

MIT
