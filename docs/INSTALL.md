# 설치

## 준비물

- Windows 10/11, Git for Windows
- PowerShell 7 (권장) 또는 Windows PowerShell 5.1
- GitHub의 **비공개(Private)** 저장소 1개 (내 세션 백업용, 처음엔 비어 있어도 됩니다)
- (선택) Claude Code, Codex CLI

PowerShell 7 설치: `winget install Microsoft.PowerShell`

## 설치하기

```powershell
git clone https://github.com/gitseon/ai-session-manager.git
cd ai-session-manager
.\install.ps1                    # 계획을 보여 주고 yes 확인 후 %LOCALAPPDATA%\ai-session-manager 에 설치
.\install.ps1 -AddToPath         # 사용자 PATH에 bin 추가 (새 터미널 필요)
.\install.ps1 -InstallSkill      # ~/.claude/skills, ~/.codex/skills 에 스킬 복사 (폴더가 있을 때만)
```

- 기존 설치 폴더는 지우지 않고 `.bak-<시각>`으로 옮깁니다.
- 스킬 폴더에 같은 이름이 이미 있으면 건드리지 않습니다(`-Force`면 `.bak`으로 옮기고 설치).
- 스크립트 실행이 막혀 있으면: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` 또는 `asm.cmd` 사용.

## 백업 저장소 연결

```powershell
asm init -Clone https://github.com/<내계정>/<비공개저장소>.git -Repo C:\asm-data
asm doctor
```

`doctor`가 "Public 저장소입니다"라고 하면 푸시하지 마세요. 저장소를 Private으로 바꾸세요.
GitHub 로그인(자격 증명 관리자 또는 `gh auth login`)은 일반 git 사용과 동일하게 미리 해 두세요. 이 도구는 토큰을 저장하지 않습니다.

## PowerShell 5.1 지원

- 코드는 5.1 문법(.NET Framework 4.7.2 이상)만 사용하고, 모든 파일에 UTF-8 BOM을 넣어 한글이 깨지지 않게 했습니다.
- CI가 Windows PowerShell 5.1에서도 같은 Pester 테스트를 실행합니다(결과는 GitHub Actions에서 확인).
- 암호화는 5.1에 없는 AES-GCM 대신 AES-CBC + HMAC-SHA256을 씁니다.

## 환경변수

| 이름 | 용도 |
|---|---|
| `ASM_HOME` | 설정·복원 백업 폴더 (기본 `~\.asm`) |
| `ASM_PASSPHRASE` | 비밀번호 입력 생략용. **보안상 비권장**, 사용 후 해제 |
| `CLAUDE_CONFIG_DIR`, `CODEX_HOME` | 세션 폴더 위치 재지정 |
| `ASM_KDF_ITERATIONS` | 테스트용 키 유도 반복 횟수(1000 이상). 평소엔 쓰지 않음 |
