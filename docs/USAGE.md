# 사용 예시

## 1. 점검

```powershell
asm doctor      # FAIL이 있으면 종료 코드 1
asm version
```

## 2. 백업

```powershell
asm list                              # 로컬 세션 (Claude + Codex)
asm backup -Session 9bf7a9a2          # 계획만 출력: 파일 수, 제외 파일, 비밀값 경고
asm backup -Session 9bf7a9a2 -Apply   # 암호화 파일만 백업 저장소 폴더에 작성 (커밋·푸시 안 함)
asm backup -Session 9bf7a9a2 -Push    # 위 + 커밋 + 푸시 + 원격 검증 (yes 확인)
asm backup -Latest 3 -Tool claude -Push -Yes
asm backup -Project C:\work\myapp -Push
```

- 세션 선택은 `-Session`(ID 앞 6자 이상), `-Latest N`, `-Project <작업폴더>`, `-All` 중 하나가 필요합니다.
- 변경이 없는 세션은 `unchanged`로 건너뜁니다.
- 세션 내용에 토큰처럼 보이는 문자열이 있으면 `blocked-secret`으로 막습니다(값은 출력하지 않음).
- 푸시 후 원격의 파일이 로컬과 같은 Git blob인지 확인하고 `원격 검증: 일치`를 출력합니다.

## 3. 상태 확인

```powershell
asm status                # 백업됨 / 백업 후 변경됨 / 미백업 / 푸시 안 된 커밋
asm list -Remote          # 백업본 목록 (제목은 비밀번호 필요: -Decrypt)
```

## 4. 복원 (다른 PC)

```powershell
asm init -Clone https://github.com/<내계정>/<비공개저장소>.git -Repo C:\asm-data
asm restore -Session 9bf7a9a2                     # 계획: 새 파일 / 동일 / 충돌
asm restore -Session 9bf7a9a2 -Apply              # 복원 + 해시·구조 검증 + 재개 명령 출력
asm restore -Session 9bf7a9a2 -ProjectPath D:\code\myapp -Apply   # Claude: 이 PC의 프로젝트 경로에 맞춰 복원
asm restore -Session 9bf7a9a2 -Apply -Overwrite   # 충돌 시 기존 파일 백업 후 덮어쓰기
```

복원 뒤 출력된 명령으로 재개합니다.

```powershell
cd D:\code\myapp; claude --resume <세션ID>
cd D:\code\myapp; codex resume <세션ID>
```

## 5. 재개가 안 될 때: 작업 인수인계

```powershell
asm restore -Session 9bf7a9a2 -Handoff     # 백업본에서 생성 (세션 파일은 설치하지 않음)
asm handoff -Session 9bf7a9a2              # 이 PC의 로컬 세션에서 생성
```

`ASM_HOME\handoffs\*.md`가 만들어집니다. 최초 요청, 마지막 대화, 백업 시점의 Git 브랜치·변경 파일, 새 세션에 붙여 넣을 안내문이 들어 있습니다. 자동 추출이므로 반드시 실제 저장소 상태와 대조하세요.

## 6. 자연어로 쓰기

`.\install.ps1 -InstallSkill`로 스킬을 설치하면 AI에게 "방금 세션 백업해줘", "백업 상태 확인해줘"라고 말할 수 있습니다. AI는 먼저 계획을 보여 주고 내 승인을 받은 뒤에만 쓰기 옵션을 붙여 실행합니다. 비밀번호는 직접 입력해야 합니다.
