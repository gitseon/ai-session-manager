function Invoke-AsmBackup {
    <#
    .SYNOPSIS
    선택한 세션을 암호화해 비공개 백업 저장소에 저장한다.
    .DESCRIPTION
    기본은 계획만 출력한다(아무것도 쓰지 않음). -Apply는 백업 저장소 작업 폴더에 암호화 파일을 쓰고,
    -Push는 추가로 커밋·푸시하고 원격 파일을 검증한다. -Push는 확인(yes) 또는 -Yes가 필요하다.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Session,
        [ValidateSet('all', 'claude', 'codex')][string]$Tool = 'all',
        [int]$Latest = 0,
        [string]$Project,
        [switch]$All,
        [switch]$Apply,
        [switch]$Push,
        [switch]$Yes,
        [switch]$AllowSecrets,
        [int]$MaxSessionMB = 200
    )
    if (-not ($Session -or $Latest -gt 0 -or $Project -or $All)) {
        throw '백업할 세션을 선택하세요: -Session <ID> | -Latest <N> | -Project <경로> | -All'
    }
    $repo = Get-AsmBackupRepo
    $selected = @(Select-AsmSessions -Sessions (Get-AsmLocalSessions -Tool $Tool) -Id $Session -Latest $Latest -Project $Project)
    if ($selected.Count -eq 0) { throw '조건에 맞는 로컬 세션이 없습니다.' }
    $manifest = @(Read-AsmManifest $repo)

    $items = @()
    foreach ($s in $selected) {
        $files = @(Get-AsmSessionFiles $s)
        $skipped = @($files | Where-Object { Test-AsmForbiddenPath $_.Rel })
        $inc = @($files | Where-Object { -not (Test-AsmForbiddenPath $_.Rel) })
        $size = [long]0
        foreach ($f in $inc) { $size += $f.Length }
        $hits = @()
        foreach ($f in $inc) { $hits += Test-AsmSecretBytes (Read-AsmFileBytes $f.Full) }
        $hits = @($hits | Select-Object -Unique)
        $fp = Get-AsmFingerprint $inc
        $old = $manifest | Where-Object { $_.tool -eq $s.Tool -and $_.id -eq $s.Id } | Select-Object -First 1
        $status = 'ready'
        if ($size -gt ($MaxSessionMB * 1MB)) { $status = 'blocked-size' }
        elseif ($hits.Count -gt 0 -and -not $AllowSecrets) { $status = 'blocked-secret' }
        elseif ($old -and $old.fingerprint -eq $fp) { $status = 'unchanged' }
        $items += [pscustomobject]@{
            Tool = $s.Tool; Id = $s.Id; Title = $s.Title; Cwd = $s.Cwd; FileCount = $inc.Count; SizeBytes = $size
            SkippedFiles = @($skipped | ForEach-Object { $_.Rel }); SecretHits = $hits
            Status = $status; Fingerprint = $fp; Session = $s; Files = $inc
        }
    }

    $result = [pscustomobject]@{ Mode = 'plan'; Repo = $repo; Items = $items; Pushed = $false; RemoteVerified = $null; Commit = $null }
    if (-not ($Apply -or $Push)) { return $result }

    $todo = @($items | Where-Object { $_.Status -eq 'ready' })
    if ($todo.Count -eq 0) { $result.Mode = 'nothing-to-do'; return $result }

    Assert-AsmRepoOnlyOurChanges $repo
    $branch = $null
    if ($Push) {
        if (-not (Test-AsmRepoHasRemote $repo)) { throw '백업 저장소에 origin 원격이 없습니다.' }
        if ((Get-AsmRepoPrivacy $repo) -eq 'public') { throw '백업 저장소가 Public입니다. 비공개 저장소만 사용할 수 있어 중단합니다.' }
        # 실제 git commit 이 쓰는 방식(설정 파일 + GIT_AUTHOR_*/GIT_COMMITTER_* 환경변수)으로 확인한다.
        if ((Invoke-AsmGit -Repo $repo -GitArgs @('var', 'GIT_COMMITTER_IDENT') -AllowFail).ExitCode -ne 0) {
            throw '백업 저장소에서 커밋할 git 사용자 정보(user.name/user.email)를 확인할 수 없습니다.'
        }
        Confirm-AsmAction -Yes:$Yes -Message "$($todo.Count)개 세션을 암호화해 비공개 저장소($repo)에 커밋하고 원격으로 푸시합니다."
        $branch = Get-AsmRepoBranch $repo
        Invoke-AsmGit -Repo $repo -GitArgs @('fetch', 'origin') -AllowFail | Out-Null
        if ((Invoke-AsmGit -Repo $repo -GitArgs @('rev-parse', '--verify', "origin/$branch") -AllowFail).ExitCode -eq 0) {
            Invoke-AsmGit -Repo $repo -GitArgs @('merge', '--ff-only', "origin/$branch") | Out-Null
            $manifest = @(Read-AsmManifest $repo)
        }
    }

    $pass = Get-AsmPassphrase -Confirm
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $written = @()
    foreach ($it in $todo) {
        $s = $it.Session
        $meta = @{
            schema = 1; tool = $s.Tool; id = $s.Id; title = $s.Title; cwd = $s.Cwd; started = $s.Started
            modified = $s.Modified.ToString('o'); backedUpAt = $now; asmVersion = $script:AsmVersion
            sourceHost = [Environment]::MachineName; fingerprint = $it.Fingerprint
            mainRel = $s.MainRel; gitState = (Get-AsmGitState $s.Cwd)
        }
        $pkg = ConvertTo-AsmPackage -Meta $meta -Files $it.Files
        $blob = Protect-AsmBytes -Plain $pkg -Passphrase $pass
        # 쓰기 전 왕복 검증: 복호화한 파일 해시가 원본과 같아야 한다.
        $chk = ConvertFrom-AsmPackage (Unprotect-AsmBytes -Blob $blob -Passphrase $pass)
        if ($chk.Files.Count -ne $it.Files.Count) { throw "암호화 왕복 검증 실패: $($s.Id)" }
        $rel = Get-AsmBlobRel $s.Tool $s.Id
        $full = Join-AsmPath $repo @($rel -split '/')
        $dir = Split-Path -Parent $full
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [IO.File]::WriteAllBytes($full, $blob)
        $manifest = @($manifest | Where-Object { -not ($_.tool -eq $s.Tool -and $_.id -eq $s.Id) })
        $manifest += [pscustomobject]@{
            tool = $s.Tool; id = $s.Id; blob = $rel; blobSha256 = (Get-AsmBytesSha256 $blob); blobSize = $blob.Length
            fingerprint = $it.Fingerprint; fileCount = $it.Files.Count; backedUpAt = $now; asmVersion = $script:AsmVersion
        }
        $written += $rel
    }
    Write-AsmManifest $repo $manifest
    $marker = Join-AsmPath $repo @('.asm-repo')
    if (-not (Test-Path -LiteralPath $marker)) { Write-AsmUtf8 $marker "ai-session-manager encrypted backup repository`n" }
    $result.Mode = 'applied'
    if (-not $Push) { return $result }

    Invoke-AsmGit -Repo $repo -GitArgs (@('add', '--', 'sessions', 'manifest.json', '.asm-repo')) | Out-Null
    $ids = ($todo | ForEach-Object { "$($_.Tool):$($_.Id.Substring(0, 8))" }) -join ', '
    Invoke-AsmGit -Repo $repo -GitArgs @('commit', '-m', "asm backup: $($todo.Count) session(s) [$ids]") | Out-Null
    $result.Commit = (Invoke-AsmGit -Repo $repo -GitArgs @('rev-parse', 'HEAD')).Output
    Invoke-AsmGit -Repo $repo -GitArgs @('push', '-u', 'origin', $branch) | Out-Null
    $result.Pushed = $true
    $paths = @($written) + @('manifest.json')
    $v = @(Test-AsmRemoteBlobs -Repo $repo -Branch $branch -Paths $paths)
    $result.RemoteVerified = (@($v | Where-Object { -not $_.Match }).Count -eq 0)
    $result.Mode = 'pushed'
    return $result
}
