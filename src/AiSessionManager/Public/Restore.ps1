function Invoke-AsmRestore {
    <#
    .SYNOPSIS
    백업 저장소의 암호화된 세션을 복호화해 이 PC의 Claude Code/Codex 세션 폴더로 복원한다.
    .DESCRIPTION
    기본은 계획만 출력한다(복호화는 하지만 아무것도 쓰지 않음). -Apply로 실제 복원한다.
    기존 파일이 있으면 같은 내용은 건너뛰고, 다른 내용은 충돌로 표시하며 덮어쓰지 않는다.
    -Overwrite를 주면 기존 파일을 ASM_HOME\restore-backups 로 복사해 둔 뒤 덮어쓴다.
    -Handoff는 세션 파일을 설치하지 않고 인수인계 문서만 만든다.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Session,
        [ValidateSet('all', 'claude', 'codex')][string]$Tool = 'all',
        [string]$ProjectPath,
        [switch]$Apply,
        [switch]$Overwrite,
        [switch]$Pull,
        [switch]$Handoff,
        [string]$Out,
        [switch]$Yes
    )
    if (-not $Session) { throw '복원할 세션을 지정하세요: -Session <ID>' }
    $repo = Get-AsmBackupRepo
    if ($Pull) {
        Confirm-AsmAction -Yes:$Yes -Message "백업 저장소($repo)에서 git fetch + merge --ff-only 를 실행합니다."
        $b = Get-AsmRepoBranch $repo
        Invoke-AsmGit -Repo $repo -GitArgs @('fetch', 'origin') | Out-Null
        if ((Invoke-AsmGit -Repo $repo -GitArgs @('rev-parse', '--verify', "origin/$b") -AllowFail).ExitCode -eq 0) {
            Invoke-AsmGit -Repo $repo -GitArgs @('merge', '--ff-only', "origin/$b") | Out-Null
        }
    }
    $entries = @(Read-AsmManifest $repo | Where-Object { $Tool -eq 'all' -or $_.tool -eq $Tool })
    $targets = @()
    foreach ($i in $Session) {
        if ($i.Length -lt 6) { throw "세션 ID는 6자 이상 입력하세요: $i" }
        $m = @($entries | Where-Object { $_.id.StartsWith($i, [StringComparison]::OrdinalIgnoreCase) })
        if ($m.Count -eq 0) { throw "백업에서 세션을 찾을 수 없습니다: $i (원격 최신 상태가 필요하면 -Pull)" }
        if ($m.Count -gt 1) { throw "ID가 모호합니다. 더 길게 입력하세요: $i" }
        $targets += $m[0]
    }
    $pass = Get-AsmPassphrase
    $results = @()
    foreach ($e in $targets) {
        $blobPath = Join-AsmPath $repo @($e.blob -split '/')
        $blob = Read-AsmFileBytes $blobPath
        if ((Get-AsmBytesSha256 $blob) -ne $e.blobSha256) { throw "백업 파일 해시가 manifest와 다릅니다(손상 또는 변조): $($e.blob)" }
        $pkg = ConvertFrom-AsmPackage (Unprotect-AsmBytes -Blob $blob -Passphrase $pass)
        $meta = $pkg.Meta

        if ($Handoff) {
            $main = $pkg.Files | Where-Object { $_.Path -eq $meta.mainRel } | Select-Object -First 1
            $msgs = @(Get-AsmMessagesFromBytes -Tool $meta.tool -Bytes $main.Bytes)
            $path = $Out
            if (-not $path) { $path = Join-AsmPath (Get-AsmHome) @('handoffs', "$($meta.tool)-$($meta.id).md") }
            Write-AsmUtf8 $path (ConvertTo-AsmHandoffText -Meta $meta -Messages $msgs) -Bom
            $results += [pscustomobject]@{ Tool = $meta.tool; Id = $meta.id; Mode = 'handoff'; HandoffPath = $path; Files = @(); Conflicts = 0; Resume = $null }
            continue
        }

        $home_ = if ($meta.tool -eq 'claude') { Get-AsmClaudeHome } else { Get-AsmCodexHome }
        $plan = @()
        foreach ($f in $pkg.Files) {
            Assert-AsmSafeRel -Tool $meta.tool -Rel $f.Path
            $rel = $f.Path
            if ($meta.tool -eq 'claude' -and $ProjectPath) {
                $parts = $rel -split '/'
                $parts[1] = ConvertTo-AsmClaudeProjectDir $ProjectPath
                $rel = $parts -join '/'
            }
            $dest = Join-AsmPath $home_ @($rel -split '/')
            $state = 'new'
            if (Test-Path -LiteralPath $dest) {
                $state = if ((Get-AsmFileSha256 $dest) -eq $f.Sha256) { 'identical' } else { 'conflict' }
            }
            $plan += [pscustomobject]@{ Rel = $rel; Dest = $dest; State = $state; File = $f }
        }
        $conflicts = @($plan | Where-Object { $_.State -eq 'conflict' }).Count
        $mode = 'plan'
        if ($Apply) {
            if ($conflicts -gt 0 -and -not $Overwrite) {
                $mode = 'blocked-conflict'
            } else {
                $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
                foreach ($p in $plan) {
                    if ($p.State -eq 'identical') { continue }
                    if ($p.State -eq 'conflict') {
                        $bk = Join-AsmPath (Get-AsmHome) @('restore-backups', $stamp, $meta.tool, $p.Rel)
                        $bkDir = Split-Path -Parent $bk
                        if (-not (Test-Path -LiteralPath $bkDir)) { New-Item -ItemType Directory -Path $bkDir -Force | Out-Null }
                        Copy-Item -LiteralPath $p.Dest -Destination $bk
                    }
                    $d = Split-Path -Parent $p.Dest
                    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
                    [IO.File]::WriteAllBytes($p.Dest, $p.File.Bytes)
                    $p.State = if ($p.State -eq 'conflict') { 'overwritten' } else { 'written' }
                }
                $mainPlan = $plan | Where-Object { $_.File.Path -eq $meta.mainRel } | Select-Object -First 1
                if ($mainPlan -and $meta.modified) {
                    try { (Get-Item -LiteralPath $mainPlan.Dest).LastWriteTimeUtc = [datetime]::Parse($meta.modified).ToUniversalTime() } catch { }
                }
                $mode = 'applied'
            }
        }
        $verify = $null
        if ($mode -eq 'applied') { $verify = Test-AsmRestoredSession -Meta $meta -Plan $plan -ProjectPath $ProjectPath }
        $results += [pscustomobject]@{
            Tool = $meta.tool; Id = $meta.id; Mode = $mode; Conflicts = $conflicts
            Files = @($plan | ForEach-Object { [pscustomobject]@{ Rel = $_.Rel; State = $_.State } })
            Verify = $verify; Resume = (Get-AsmResumeCommand -Meta $meta -ProjectPath $ProjectPath); HandoffPath = $null
        }
    }
    return $results
}

function Get-AsmResumeCommand {
    param($Meta, [string]$ProjectPath)
    $cwd = if ($ProjectPath) { $ProjectPath } else { $Meta.cwd }
    if ($Meta.tool -eq 'claude') { return "cd `"$cwd`"; claude --resume $($Meta.id)" }
    return "cd `"$cwd`"; codex resume $($Meta.id)"
}

function Test-AsmRestoredSession {
    # 구조 검증: 파일 존재·해시 일치·JSONL 파싱·세션 ID 일치. 실제 대화 재개는 CLI에서 사람이 확인해야 한다.
    param($Meta, [object[]]$Plan, [string]$ProjectPath)
    $checks = @()
    $ok = $true
    foreach ($p in $Plan) {
        $exists = Test-Path -LiteralPath $p.Dest
        $same = $exists -and ((Get-AsmFileSha256 $p.Dest) -eq $p.File.Sha256)
        if (-not $same) { $ok = $false }
    }
    $checks += [pscustomobject]@{ Check = '파일 존재·해시 일치'; Ok = $ok }
    $main = $Plan | Where-Object { $_.File.Path -eq $Meta.mainRel } | Select-Object -First 1
    $parsed = $false
    if ($main -and (Test-Path -LiteralPath $main.Dest)) {
        $head = Read-AsmJsonlHead $main.Dest 5
        $parsed = (@($head).Count -gt 0)
    }
    $checks += [pscustomobject]@{ Check = 'JSONL 파싱'; Ok = $parsed }
    if ($Meta.tool -eq 'claude') {
        $leaf = if ($main) { [IO.Path]::GetFileNameWithoutExtension($main.Dest) } else { '' }
        $checks += [pscustomobject]@{ Check = '파일명 = 세션 ID'; Ok = ($leaf -eq $Meta.id) }
    }
    $cwd = if ($ProjectPath) { $ProjectPath } else { $Meta.cwd }
    $checks += [pscustomobject]@{ Check = "작업 폴더 존재 ($cwd)"; Ok = ($cwd -and (Test-Path -LiteralPath $cwd)) }
    $cli = if ($Meta.tool -eq 'claude') { 'claude' } else { 'codex' }
    $checks += [pscustomobject]@{ Check = "$cli CLI 설치"; Ok = [bool](Get-Command $cli -ErrorAction SilentlyContinue) }
    return $checks
}
