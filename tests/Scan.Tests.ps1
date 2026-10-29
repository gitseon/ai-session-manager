BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    Import-AsmForTest
}

Describe 'Scan' {
    It '인증·키 파일 이름은 업로드 금지로 판정한다' {
        foreach ($n in @('projects/x/.credentials.json', 'auth.json', 'a/b/id_rsa', 'x/my.pem', 'x/.env', 'x/oauth-cache.json')) {
            (Invoke-Private { param($r) Test-AsmForbiddenPath $r } @($n)) | Should -BeTrue
        }
    }
    It '일반 세션 파일은 금지하지 않는다' {
        (Invoke-Private { Test-AsmForbiddenPath 'projects/-home-x/abc.jsonl' }) | Should -BeFalse
    }
    It '비밀값 패턴을 이름으로만 보고한다' {
        $fake = 'token=' + 'ghp_' + ('a' * 36)
        $hits = Invoke-Private { param($t) Test-AsmSecretText $t } @($fake)
        ($hits -join ',') | Should -Match 'GitHub'
        ($hits -join ',') | Should -Not -Match 'ghp_'
    }
    It '평범한 텍스트는 탐지하지 않는다' {
        @(Invoke-Private { Test-AsmSecretText 'just a normal sentence' }).Count | Should -Be 0
    }
}
