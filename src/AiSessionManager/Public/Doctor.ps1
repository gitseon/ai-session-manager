function Invoke-AsmDoctor {
    [CmdletBinding()]
    param()
    $r = New-Object System.Collections.ArrayList
    function Add-Check($name, $status, $detail) { [void]$r.Add([pscustomobject]@{ Check = $name; Status = $status; Detail = $detail }) }

    $v = $PSVersionTable.PSVersion
    if ($v.Major -ge 7) { Add-Check 'PowerShell' 'OK' "$v (기준 환경)" }
    elseif ($v.Major -eq 5) { Add-Check 'PowerShell' 'WARN' "$v (Windows PowerShell 5.1: 기본 기능 지원, PowerShell 7 권장)" }
    else { Add-Check 'PowerShell' 'FAIL' "$v 는 지원하지 않습니다" }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { Add-Check 'git' 'OK' ((& git --version) -join '') } else { Add-Check 'git' 'FAIL' 'git이 설치되어 있지 않습니다' }

    foreach ($t in @(@('claude', 'Claude Code'), @('codex', 'Codex'))) {
        $c = Get-Command $t[0] -ErrorAction SilentlyContinue
        if ($c) {
            $ver = ''
            try { $ver = ((& $t[0] --version 2>&1) | Select-Object -First 1) } catch { }
            Add-Check "$($t[1]) CLI" 'OK' "$ver"
        } else { Add-Check "$($t[1]) CLI" 'WARN' '설치되지 않음 (복원 후 재개 검증 불가)' }
    }

    $ch = Get-AsmClaudeHome
    $cn = @(Get-AsmClaudeSessions).Count
    if (Test-Path -LiteralPath $ch) { Add-Check 'Claude 세션 폴더' 'OK' "$ch (세션 $($cn)개)" } else { Add-Check 'Claude 세션 폴더' 'WARN' "없음: $ch" }
    $xh = Get-AsmCodexHome
    $xn = @(Get-AsmCodexSessions).Count
    if (Test-Path -LiteralPath $xh) { Add-Check 'Codex 세션 폴더' 'OK' "$xh (세션 $($xn)개)" } else { Add-Check 'Codex 세션 폴더' 'WARN' "없음: $xh" }

    try {
        $repo = Get-AsmBackupRepo
        Add-Check '백업 저장소' 'OK' $repo
        if (Test-AsmRepoHasRemote $repo) {
            $p = Get-AsmRepoPrivacy $repo
            if ($p -eq 'public') { Add-Check '저장소 공개 여부' 'FAIL' 'Public 저장소입니다. 비공개로 바꾸거나 다른 저장소를 쓰세요' }
            elseif ($p -eq 'private') { Add-Check '저장소 공개 여부' 'OK' '비공개(비로그인 접근 불가)' }
            else { Add-Check '저장소 공개 여부' 'WARN' '자동 확인 불가: GitHub에서 Private인지 직접 확인하세요' }
        } else { Add-Check '백업 저장소 원격' 'WARN' 'origin 원격이 없습니다 (푸시 불가)' }
    } catch { Add-Check '백업 저장소' 'WARN' $_.Exception.Message }

    try {
        $blob = Protect-AsmBytes -Plain ([byte[]](1, 2, 3, 4)) -Passphrase 'selftest' -Iterations 1000
        $back = Unprotect-AsmBytes -Blob $blob -Passphrase 'selftest'
        if ($back.Length -eq 4 -and $back[3] -eq 4) { Add-Check '암호화 자체 시험' 'OK' 'AES-256-CBC + HMAC-SHA256' } else { Add-Check '암호화 자체 시험' 'FAIL' '복호화 결과 불일치' }
    } catch { Add-Check '암호화 자체 시험' 'FAIL' $_.Exception.Message }

    if ($env:ASM_PASSPHRASE) { Add-Check '비밀번호 환경변수' 'WARN' 'ASM_PASSPHRASE 설정됨 (사용 후 해제 권장)' } else { Add-Check '비밀번호 환경변수' 'OK' '미설정 (실행 시 입력)' }
    return $r.ToArray()
}
