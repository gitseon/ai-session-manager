function Get-AsmVersionInfo {
    return [pscustomobject]@{
        Name = 'ai-session-manager'; Version = $script:AsmVersion
        PowerShell = $PSVersionTable.PSVersion.ToString()
    }
}

function Initialize-Asm {
    <#
    .SYNOPSIS
    백업 저장소(로컬 클론 경로)를 설정한다. -Clone을 주면 해당 URL을 -Repo 경로에 클론한다.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repo, [string]$Clone, [switch]$Yes)
    if ($Clone) {
        if (Test-Path -LiteralPath $Repo) { throw "이미 존재하는 경로입니다. 클론하지 않습니다: $Repo" }
        Confirm-AsmAction -Yes:$Yes -Message "$Clone 을(를) $Repo 에 클론합니다."
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $o = & git clone $Clone $Repo 2>&1 } finally { $ErrorActionPreference = $old }
        if ($LASTEXITCODE -ne 0) { throw "git clone 실패: $($o -join ' ')" }
    }
    if (-not (Test-Path -LiteralPath (Join-AsmPath $Repo @('.git')))) { throw "Git 저장소가 아닙니다: $Repo" }
    $full = (Resolve-Path -LiteralPath $Repo).Path
    Set-AsmConfigValue -Name 'backupRepo' -Value $full
    return [pscustomobject]@{ BackupRepo = $full; Config = (Get-AsmConfigPath); Privacy = (Get-AsmRepoPrivacy $full) }
}

function Get-AsmSessionList {
    [CmdletBinding()]
    param(
        [ValidateSet('all', 'claude', 'codex')][string]$Tool = 'all',
        [switch]$Remote,
        [switch]$Decrypt
    )
    if (-not $Remote) {
        return @(Get-AsmLocalSessions -Tool $Tool | Sort-Object Modified -Descending |
            ForEach-Object { [pscustomobject]@{ Tool = $_.Tool; Id = $_.Id; Modified = $_.Modified; Cwd = $_.Cwd; Title = $_.Title } })
    }
    $repo = Get-AsmBackupRepo
    $entries = @(Read-AsmManifest $repo | Where-Object { $Tool -eq 'all' -or $_.tool -eq $Tool })
    $pass = $null
    if ($Decrypt) { $pass = Get-AsmPassphrase }
    $rows = @()
    foreach ($e in $entries) {
        $title = ''
        $cwd = ''
        if ($Decrypt) {
            $pkg = ConvertFrom-AsmPackage (Unprotect-AsmBytes -Blob (Read-AsmFileBytes (Join-AsmPath $repo @($e.blob -split '/'))) -Passphrase $pass)
            $title = $pkg.Meta.title
            $cwd = $pkg.Meta.cwd
        }
        $rows += [pscustomobject]@{ Tool = $e.tool; Id = $e.id; BackedUpAt = $e.backedUpAt; SizeBytes = $e.blobSize; Cwd = $cwd; Title = $title }
    }
    return $rows
}

function Get-AsmStatus {
    [CmdletBinding()]
    param([ValidateSet('all', 'claude', 'codex')][string]$Tool = 'all')
    $repo = Get-AsmBackupRepo
    $manifest = @(Read-AsmManifest $repo)
    $branch = (Invoke-AsmGit -Repo $repo -GitArgs @('symbolic-ref', '--short', 'HEAD') -AllowFail).Output
    $ahead = $null
    $behind = $null
    $cnt = Invoke-AsmGit -Repo $repo -GitArgs @('rev-list', '--left-right', '--count', '@{u}...HEAD') -AllowFail
    if ($cnt.ExitCode -eq 0 -and $cnt.Output -match '^(\d+)\s+(\d+)$') { $behind = [int]$Matches[1]; $ahead = [int]$Matches[2] }
    $local = @(Get-AsmLocalSessions -Tool $Tool)
    $rows = @()
    foreach ($s in $local) {
        $e = $manifest | Where-Object { $_.tool -eq $s.Tool -and $_.id -eq $s.Id } | Select-Object -First 1
        $state = 'not-backed-up'
        if ($e) {
            $inc = @(Get-AsmSessionFiles $s | Where-Object { -not (Test-AsmForbiddenPath $_.Rel) })
            $state = if ((Get-AsmFingerprint $inc) -eq $e.fingerprint) { 'up-to-date' } else { 'changed-since-backup' }
        }
        $rows += [pscustomobject]@{ Tool = $s.Tool; Id = $s.Id; State = $state; Title = $s.Title }
    }
    $localKeys = @($local | ForEach-Object { "$($_.Tool)/$($_.Id)" })
    $remoteOnly = @($manifest | Where-Object { ($Tool -eq 'all' -or $_.tool -eq $Tool) -and ("$($_.tool)/$($_.id)" -notin $localKeys) })
    return [pscustomobject]@{
        Repo = $repo; Branch = $branch; Entries = $manifest.Count
        UnpushedCommits = $ahead; UnpulledCommits = $behind; UncommittedPaths = @(Get-AsmRepoDirtyPaths $repo).Count
        UpToDate = @($rows | Where-Object State -eq 'up-to-date').Count
        Changed = @($rows | Where-Object State -eq 'changed-since-backup').Count
        NotBackedUp = @($rows | Where-Object State -eq 'not-backed-up').Count
        RemoteOnly = $remoteOnly.Count
        Sessions = $rows
    }
}

function New-AsmHandoff {
    <#
    .SYNOPSIS
    원래 대화를 재개할 수 없을 때 쓰는 작업 인수인계 문서를 만든다(로컬 세션 기준). 백업 기준은 restore -Handoff.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Session, [ValidateSet('all', 'claude', 'codex')][string]$Tool = 'all', [string]$Out)
    $s = (Select-AsmSessions -Sessions (Get-AsmLocalSessions -Tool $Tool) -Id @($Session))[0]
    $main = Join-AsmPath $s.Root @($s.MainRel -split '/')
    $msgs = @(Get-AsmMessagesFromBytes -Tool $s.Tool -Bytes (Read-AsmFileBytes $main))
    $meta = [pscustomobject]@{
        tool = $s.Tool; id = $s.Id; cwd = $s.Cwd; started = $s.Started; modified = $s.Modified.ToString('o')
        backedUpAt = '(로컬 세션에서 직접 생성)'; gitState = (Get-AsmGitState $s.Cwd)
    }
    $path = $Out
    if (-not $path) { $path = Join-AsmPath (Get-AsmHome) @('handoffs', "$($s.Tool)-$($s.Id).md") }
    Write-AsmUtf8 $path (ConvertTo-AsmHandoffText -Meta $meta -Messages $msgs) -Bom
    return [pscustomobject]@{ Tool = $s.Tool; Id = $s.Id; HandoffPath = $path }
}
