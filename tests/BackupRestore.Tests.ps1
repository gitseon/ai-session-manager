BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    Import-AsmForTest
    Set-TestGitIdentity
    $env:ASM_PASSPHRASE = 'test-passphrase'
    $env:ASM_KDF_ITERATIONS = '1000'

    # Pester 5 의 TestDrive 는 블록이 끝날 때 그 블록 안에서 새로 생긴 파일을 지운다.
    # 가짜 원격(bare 저장소)에 푸시로 생긴 객체가 사라지면 복원 단계가 깨지므로 전용 임시 폴더를 쓴다.
    $script:root = New-TestDir ([IO.Path]::GetTempPath()) ('asm-e2e-' + [guid]::NewGuid().ToString('N'))
    # 원본 PC(A)
    $script:aClaude = New-TestDir $script:root 'a-claude'
    $script:aCodex = New-TestDir $script:root 'a-codex'
    $script:cid = '11111111-2222-3333-4444-555555555555'
    $script:xid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    $script:cwd = (New-TestDir $script:root 'proj-a')
    New-FakeClaudeSession -ClaudeHome $script:aClaude -Cwd $script:cwd -Id $script:cid -Prompt 'build the thing' -WithCompanion | Out-Null
    New-FakeCodexSession -CodexHome $script:aCodex -Cwd $script:cwd -Id $script:xid | Out-Null
    # 인증 파일(절대 업로드되면 안 됨)
    [IO.File]::WriteAllText((Join-Path $script:aClaude '.credentials.json'), '{"claudeAiOauth":{"accessToken":"FAKE-DO-NOT-UPLOAD"}}')
    [IO.File]::WriteAllText((Join-Path $script:aCodex 'auth.json'), '{"tokens":{"access_token":"FAKE-DO-NOT-UPLOAD"}}')
    # 비공개 원격(로컬 bare)과 작업 클론
    $script:remote = Join-Path $script:root 'remote.git'
    Invoke-TestGit init -q --bare -b main $script:remote | Out-Null
    $script:work = Join-Path $script:root 'work-a'
    Invoke-TestGit clone -q $script:remote $script:work | Out-Null
    Invoke-TestGit -C $script:work checkout -q -B main | Out-Null

    $env:ASM_HOME = New-TestDir $script:root 'asmhome-a'
    $env:CLAUDE_CONFIG_DIR = $script:aClaude
    $env:CODEX_HOME = $script:aCodex
    Initialize-Asm -Repo $script:work | Out-Null
}
AfterAll {
    try { Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    Remove-Item Env:ASM_PASSPHRASE, Env:ASM_KDF_ITERATIONS, Env:ASM_HOME, Env:CLAUDE_CONFIG_DIR, Env:CODEX_HOME -ErrorAction SilentlyContinue
}

Describe 'backup' {
    It '선택 없이 실행하면 거부한다' {
        { Invoke-AsmBackup } | Should -Throw
    }
    It '기본은 계획만 출력하고 아무것도 쓰지 않는다' {
        $r = Invoke-AsmBackup -Session $script:cid
        $r.Mode | Should -Be 'plan'
        (Test-Path (Join-Path $script:work 'sessions')) | Should -BeFalse
        (Test-Path (Join-Path $script:work 'manifest.json')) | Should -BeFalse
    }
    It '계획에서 인증 관련 동반 파일을 제외한다' {
        $r = Invoke-AsmBackup -Session $script:cid
        ($r.Items[0].SkippedFiles -join ',') | Should -Match 'oauth-token.json'
        $r.Items[0].FileCount | Should -Be 2
    }
    It '비밀값이 들어 있는 세션은 차단한다' {
        $leak = '33333333-2222-3333-4444-555555555555'
        New-FakeClaudeSession -ClaudeHome $script:aClaude -Cwd $script:cwd -Id $leak -Prompt ('my key ghp_' + ('b' * 36)) | Out-Null
        $r = Invoke-AsmBackup -Session $leak
        $r.Items[0].Status | Should -Be 'blocked-secret'
        $r2 = Invoke-AsmBackup -Session $leak -Apply
        $r2.Mode | Should -Be 'nothing-to-do'
    }
    It '-Push: 암호화·커밋·푸시하고 원격 파일을 검증한다' {
        $r = Invoke-AsmBackup -Session $script:cid, $script:xid -Push -Yes
        $r.Mode | Should -Be 'pushed'
        $r.Pushed | Should -BeTrue
        $r.RemoteVerified | Should -BeTrue
        (Invoke-TestGit -C $script:remote log --oneline main | Measure-Object).Count | Should -Be 1
    }
    It '원격 저장소에 평문·인증 파일·민감 문자열이 없다' {
        $files = (Invoke-TestGit -C $script:remote ls-tree -r --name-only main) -join "`n"
        $files | Should -Match 'sessions/claude/'
        $files | Should -Not -Match 'credentials'
        $files | Should -Not -Match 'auth\.json'
        $files | Should -Not -Match 'oauth'
        $files | Should -Not -Match '\.jsonl'
        $tmp = New-TestDir $script:root 'verify-clone'
        Invoke-TestGit clone -q $script:remote (Join-Path $tmp 'c') | Out-Null
        $hit = Get-ChildItem (Join-Path $tmp 'c') -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
            Where-Object { [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($_.FullName)) -match 'FAKE-DO-NOT-UPLOAD|build the thing|working on it' }
        @($hit).Count | Should -Be 0
    }
    It 'manifest.json 은 BOM 없는 UTF-8 JSON 이다' {
        [IO.File]::ReadAllBytes((Join-Path $script:work 'manifest.json'))[0] | Should -Be 0x7B
    }
    It '변경 없는 재백업은 unchanged 로 건너뛴다' {
        $r = Invoke-AsmBackup -Session $script:cid
        $r.Items[0].Status | Should -Be 'unchanged'
    }
    It 'status 가 백업 상태를 보여 준다' {
        $s = Get-AsmStatus
        $s.UpToDate | Should -Be 2
        $s.UnpushedCommits | Should -Be 0
    }
    It '세션이 바뀌면 changed-since-backup 으로 표시한다' {
        Add-Content -LiteralPath (Join-Path $script:aClaude "projects/$([regex]::Replace($script:cwd,'[^A-Za-z0-9]','-'))/$($script:cid).jsonl") -Value '{"type":"user","message":{"role":"user","content":"more"}}'
        (Get-AsmStatus).Changed | Should -Be 1
    }
    It '백업 저장소에 무관한 변경이 있으면 건드리지 않고 중단한다' {
        [IO.File]::WriteAllText((Join-Path $script:work 'notes.txt'), 'user file')
        { Invoke-AsmBackup -Session $script:cid -Apply } | Should -Throw
        (Get-Content (Join-Path $script:work 'notes.txt') -Raw) | Should -Be 'user file'
        Remove-Item (Join-Path $script:work 'notes.txt')
    }
}

Describe 'restore (다른 PC 시뮬레이션)' {
    BeforeAll {
        $script:bClaude = New-TestDir $script:root 'b-claude'
        $script:bCodex = New-TestDir $script:root 'b-codex'
        $script:work2 = Join-Path $script:root 'work-b'
        Invoke-TestGit clone -q $script:remote $script:work2 | Out-Null
        $env:ASM_HOME = New-TestDir $script:root 'asmhome-b'
        $env:CLAUDE_CONFIG_DIR = $script:bClaude
        $env:CODEX_HOME = $script:bCodex
        Initialize-Asm -Repo $script:work2 | Out-Null
    }
    It '기본은 계획만 출력한다' {
        $r = Invoke-AsmRestore -Session $script:cid
        $r[0].Mode | Should -Be 'plan'
        @(Get-ChildItem $script:bClaude -Recurse -File).Count | Should -Be 0
    }
    It '틀린 비밀번호로는 복원할 수 없다' {
        $env:ASM_PASSPHRASE = 'wrong'
        { Invoke-AsmRestore -Session $script:cid } | Should -Throw
        $env:ASM_PASSPHRASE = 'test-passphrase'
    }
    It '-Apply 로 복원하고 해시·구조를 검증한다' {
        $r = Invoke-AsmRestore -Session $script:cid -Apply
        $r[0].Mode | Should -Be 'applied'
        (@($r[0].Verify | Where-Object { $_.Check -match '해시|JSONL|세션 ID' -and -not $_.Ok })).Count | Should -Be 0
        $dir = [regex]::Replace($script:cwd, '[^A-Za-z0-9]', '-')
        $restored = Join-Path $script:bClaude "projects/$dir/$($script:cid).jsonl"
        (Test-Path $restored) | Should -BeTrue
        (Test-Path (Join-Path $script:bClaude "projects/$dir/$($script:cid)/tool-results/out.txt")) | Should -BeTrue
        (Test-Path (Join-Path $script:bClaude "projects/$dir/$($script:cid)/tool-results/oauth-token.json")) | Should -BeFalse
        $r[0].Resume | Should -Match 'claude --resume'
    }
    It '-ProjectPath 로 다른 작업 폴더 이름에 맞춰 복원한다' {
        $np = 'D:\other\place'
        $r = Invoke-AsmRestore -Session $script:cid -ProjectPath $np -Apply
        (Test-Path (Join-Path $script:bClaude "projects/D--other-place/$($script:cid).jsonl")) | Should -BeTrue
    }
    It '기존 파일은 덮어쓰지 않고 충돌로 표시한다' {
        $dir = [regex]::Replace($script:cwd, '[^A-Za-z0-9]', '-')
        $f = Join-Path $script:bClaude "projects/$dir/$($script:cid).jsonl"
        Set-Content -LiteralPath $f -Value 'LOCAL EDIT'
        $r = Invoke-AsmRestore -Session $script:cid -Apply
        $r[0].Mode | Should -Be 'blocked-conflict'
        (Get-Content -LiteralPath $f -Raw).Trim() | Should -Be 'LOCAL EDIT'
    }
    It '-Overwrite 는 기존 파일을 백업한 뒤 덮어쓴다' {
        $dir = [regex]::Replace($script:cwd, '[^A-Za-z0-9]', '-')
        $f = Join-Path $script:bClaude "projects/$dir/$($script:cid).jsonl"
        $r = Invoke-AsmRestore -Session $script:cid -Apply -Overwrite
        $r[0].Mode | Should -Be 'applied'
        (Get-Content -LiteralPath $f -Raw) | Should -Match 'build the thing'
        $bk = Get-ChildItem (Join-Path $env:ASM_HOME 'restore-backups') -Recurse -File | Where-Object { $_.Name -eq "$($script:cid).jsonl" }
        @($bk).Count | Should -Be 1
        (Get-Content -LiteralPath $bk[0].FullName -Raw).Trim() | Should -Be 'LOCAL EDIT'
    }
    It 'Codex 세션도 원래 날짜 폴더 구조로 복원한다' {
        $r = Invoke-AsmRestore -Session $script:xid -Apply
        $r[0].Mode | Should -Be 'applied'
        @(Get-ChildItem (Join-Path $script:bCodex 'sessions') -Recurse -Filter "*$($script:xid).jsonl").Count | Should -Be 1
        $r[0].Resume | Should -Match 'codex resume'
    }
    It '-Handoff 는 세션을 설치하지 않고 인수인계 문서를 만든다' {
        $out = Join-Path $script:root 'handoff.md'
        $r = Invoke-AsmRestore -Session $script:cid -Handoff -Out $out
        $r[0].Mode | Should -Be 'handoff'
        $b = [IO.File]::ReadAllBytes($out)
        ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeTrue
        $t = Get-Content -LiteralPath $out -Raw
        $t | Should -Match '최초 요청'
        $t | Should -Match 'build the thing'
        $t | Should -Match 'working on it'
    }
}
