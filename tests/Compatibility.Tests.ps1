Describe 'Windows PowerShell 5.1 호환 규칙' {
    BeforeAll {
        $script:psFiles = Get-ChildItem (Split-Path -Parent $PSScriptRoot) -Recurse -Include *.ps1, *.psm1, *.psd1 -File |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
    }
    It '모든 PowerShell 파일은 UTF-8 BOM 이 있다(5.1 에서 한글 깨짐 방지)' {
        foreach ($f in $script:psFiles) {
            $b = [IO.File]::ReadAllBytes($f.FullName)
            ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeTrue
        }
    }
    It 'PowerShell 7 전용 문법(??, 삼항, &&)을 쓰지 않는다' {
        foreach ($f in ($script:psFiles | Where-Object { $_.Name -notmatch 'Tests\.ps1$' })) {
            $t = [IO.File]::ReadAllText($f.FullName)
            $t | Should -Not -Match '\?\?'
            $t | Should -Not -Match '\)\s*\?\s*[^\s]+\s*:\s'
            $t | Should -Not -Match '\s&&\s'
        }
    }
    It '모든 파일이 구문 오류 없이 파싱된다' {
        foreach ($f in $script:psFiles) {
            $errs = $null
            [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
            @($errs).Count | Should -Be 0
        }
    }
}
