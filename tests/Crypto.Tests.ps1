BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    Import-AsmForTest
}

Describe 'Crypto' {
    It '암호화 후 복호화하면 원문이 같다' {
        $plain = [Text.Encoding]::UTF8.GetBytes('안녕 세션 데이터 ' * 100)
        $blob = Invoke-Private { param($p) Protect-AsmBytes -Plain $p -Passphrase 'pw-1' -Iterations 1000 } @(, $plain)
        $back = Invoke-Private { param($b) Unprotect-AsmBytes -Blob $b -Passphrase 'pw-1' } @(, $blob)
        [Text.Encoding]::UTF8.GetString($back) | Should -BeExactly ([Text.Encoding]::UTF8.GetString($plain))
    }
    It '같은 입력도 매번 다른 암호문이 나온다' {
        $plain = [byte[]](1..50)
        $a = Invoke-Private { param($p) Protect-AsmBytes -Plain $p -Passphrase 'pw' -Iterations 1000 } @(, $plain)
        $b = Invoke-Private { param($p) Protect-AsmBytes -Plain $p -Passphrase 'pw' -Iterations 1000 } @(, $plain)
        [Convert]::ToBase64String($a) | Should -Not -Be ([Convert]::ToBase64String($b))
    }
    It '틀린 비밀번호는 거부한다' {
        $blob = Invoke-Private { Protect-AsmBytes -Plain ([byte[]](1..20)) -Passphrase 'right' -Iterations 1000 }
        { Invoke-Private { param($b) Unprotect-AsmBytes -Blob $b -Passphrase 'wrong' } @(, $blob) } | Should -Throw
    }
    It '한 바이트라도 변조되면 거부한다' {
        $blob = Invoke-Private { Protect-AsmBytes -Plain ([byte[]](1..64)) -Passphrase 'pw' -Iterations 1000 }
        $blob[50] = $blob[50] -bxor 1
        { Invoke-Private { param($b) Unprotect-AsmBytes -Blob $b -Passphrase 'pw' } @(, $blob) } | Should -Throw
    }
    It '비허용 반복 횟수 헤더는 거부한다' {
        $blob = Invoke-Private { Protect-AsmBytes -Plain ([byte[]](1..20)) -Passphrase 'pw' -Iterations 1000 }
        $blob[4] = 0x7F
        { Invoke-Private { param($b) Unprotect-AsmBytes -Blob $b -Passphrase 'pw' } @(, $blob) } | Should -Throw
    }
}
