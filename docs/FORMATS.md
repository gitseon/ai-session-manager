# 세션 저장 형식과 검증 상태

공식적으로 문서화된 형식이 아니므로 CLI 업데이트로 바뀔 수 있습니다. `asm doctor`와 복원 구조 검증으로 확인하세요.

## Claude Code

- 위치: `<CLAUDE_CONFIG_DIR 또는 ~/.claude>/projects/<작업폴더 경로의 영숫자 외 문자를 '-'로 바꾼 이름>/<세션UUID>.jsonl`
  - 예: `/home/user/proj` → `-home-user-proj`, `C:\Users\me\proj` → `C--Users-me-proj`
- 동반 폴더: 같은 이름의 `<세션UUID>/` (tool-results 등). 있으면 함께 백업합니다.
- JSONL 각 줄에 `type`, `cwd`, `sessionId`, `timestamp`, `message{role,content}`가 있습니다.
- 재개: 해당 작업 폴더에서 `claude --resume <세션UUID>`.
- **검증 상태**: v0.1.0 개발 중 Claude Code 2.1.312(Linux)의 실제 세션 파일을 읽어 위 구조와 경로 규칙(`/home/user/job-search-ai-workspace` → `-home-user-job-search-ai-workspace`)을 확인했습니다. Windows 경로 규칙(`C--...`)은 같은 치환 규칙의 적용이며 **Windows 실기기에서는 미검증**입니다.
- 복원 시 `-ProjectPath`를 주면 폴더 이름만 바꾸며, JSONL 내부의 `cwd` 값은 수정하지 않습니다(원본 보존). 내부 `cwd`와 다른 폴더에서 재개할 때의 동작은 미검증입니다.

## Codex

- 위치: `<CODEX_HOME 또는 ~/.codex>/sessions/YYYY/MM/DD/rollout-<시각>-<UUID>.jsonl`
- 첫 줄 `session_meta`의 `payload.id`, `payload.cwd`를 사용하고(구형은 최상위 `id`), 대화는 `response_item`의 `message`에서 추출합니다.
- 재개: `codex resume <세션ID>`.
- **검증 상태**: 개발 환경에 Codex가 없어 **실제 설치 버전으로는 미검증**입니다. 알려진 구조를 바탕으로 만든 가짜 세션으로만 시험했습니다. 내 PC에서 `asm doctor`, `asm list -Tool codex`로 목록과 제목이 나오는지 먼저 확인하세요.

## 제외하는 것

`.credentials.json`, `auth.json`, 설정 파일, 플러그인·캐시, Claude의 `file-history`·`todos`·`shell-snapshots`, Codex의 `config.toml`·`archived_sessions` 등은 백업 대상이 아닙니다(v0.1.0).

## 백업 파일 형식 (`.asm`)

`"ASM1"(4) | PBKDF2 반복 횟수 int32 BE(4) | salt(16) | iv(16) | AES-256-CBC 암호문 | HMAC-SHA256(32)`
복호화하면 gzip → `[메타 길이 int32 BE][메타 JSON][파일 바이트 연속]` 입니다. 메타에 도구·세션ID·제목·작업 경로·Git 상태·파일 목록(경로, 크기, SHA-256)이 들어 있습니다.
