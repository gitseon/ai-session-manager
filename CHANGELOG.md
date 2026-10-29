# 변경 이력

## 0.1.0 (개발 중)

- 핵심 엔진: 암호화(AES-256-CBC + HMAC-SHA256, PBKDF2), Claude Code·Codex 세션 탐색, 선별 백업, GitHub 푸시와 원격 blob 검증, 비파괴 복원, 구조 검증, 인수인계 문서.
- CLI: `asm doctor | backup | restore | list | status | version` (+ `init`, `handoff`).
- 설치 스크립트, AI 스킬 초안(`skills/ai-session-manager/SKILL.md`), Pester 테스트, Windows CI.
