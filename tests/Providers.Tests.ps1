BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    Import-AsmForTest
    $script:root = New-TestDir $TestDrive 'prov'
    $env:CLAUDE_CONFIG_DIR = New-TestDir $script:root 'claude'
    $env:CODEX_HOME = New-TestDir $script:root 'codex'
    $script:cid = '11111111-2222-3333-4444-555555555555'
    $script:xid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    New-FakeClaudeSession -ClaudeHome $env:CLAUDE_CONFIG_DIR -Cwd 'C:\work\proj' -Id $script:cid -Prompt 'build the thing' -WithCompanion | Out-Null
    New-FakeCodexSession -CodexHome $env:CODEX_HOME -Cwd '/work/x' -Id $script:xid | Out-Null
}
AfterAll {
    Remove-Item Env:CLAUDE_CONFIG_DIR, Env:CODEX_HOME -ErrorAction SilentlyContinue
}

Describe 'Providers' {
    It 'Claude 프로젝트 폴더 이름 규칙(영숫자 외 문자는 -)' {
        (Invoke-Private { ConvertTo-AsmClaudeProjectDir 'C:\Users\me\proj' }) | Should -BeExactly 'C--Users-me-proj'
        (Invoke-Private { ConvertTo-AsmClaudeProjectDir '/home/user/job-search' }) | Should -BeExactly '-home-user-job-search'
    }
    It 'Claude 세션을 찾고 cwd·제목을 읽는다' {
        $s = @(Get-AsmSessionList -Tool claude)
        $s.Count | Should -Be 1
        $s[0].Id | Should -BeExactly $script:cid
        $s[0].Cwd | Should -BeExactly 'C:\work\proj'
        $s[0].Title | Should -Be 'build the thing'
    }
    It 'Codex 세션을 찾고 id·cwd·제목을 읽는다' {
        $s = @(Get-AsmSessionList -Tool codex)
        $s.Count | Should -Be 1
        $s[0].Id | Should -BeExactly $script:xid
        $s[0].Cwd | Should -BeExactly '/work/x'
        $s[0].Title | Should -Be 'fix the bug'
    }
    It '세션 ID 접두사로 선택하고 모호하면 오류' {
        $all = Invoke-Private { Get-AsmLocalSessions }
        (Invoke-Private { param($a) (Select-AsmSessions -Sessions $a -Id @('111111'))[0].Id } @(, $all)) | Should -BeExactly $script:cid
        { Invoke-Private { param($a) Select-AsmSessions -Sessions $a -Id @('zzzzzz') } @(, $all) } | Should -Throw
    }
    It '복원 경로가 홈 밖으로 나가는 것을 막는다' {
        { Invoke-Private { Assert-AsmSafeRel -Tool 'claude' -Rel 'projects/../../evil' } } | Should -Throw
        { Invoke-Private { Assert-AsmSafeRel -Tool 'codex' -Rel 'C:/Windows/x' } } | Should -Throw
        { Invoke-Private { Assert-AsmSafeRel -Tool 'claude' -Rel 'projects/-a/b.jsonl' } } | Should -Not -Throw
    }
}
