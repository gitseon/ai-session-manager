function Get-AsmManifestPath {
    param([string]$Repo)
    return (Join-AsmPath $Repo @('manifest.json'))
}

function Read-AsmManifest {
    param([string]$Repo)
    $p = Get-AsmManifestPath $Repo
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    $m = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($m.entries)
}

function Write-AsmManifest {
    param([string]$Repo, [object[]]$Entries)
    $sorted = @($Entries | Sort-Object tool, id)
    $obj = [ordered]@{ schema = 1; entries = $sorted }
    Write-AsmUtf8 (Get-AsmManifestPath $Repo) (ConvertTo-Json -InputObject $obj -Depth 5)
}

function Get-AsmBlobRel {
    param([string]$Tool, [string]$Id)
    return "sessions/$Tool/$Id.asm"
}

function Get-AsmRepoBranch {
    param([string]$Repo)
    return (Invoke-AsmGit -Repo $Repo -GitArgs @('symbolic-ref', '--short', 'HEAD')).Output
}

function Test-AsmRepoHasRemote {
    param([string]$Repo)
    return ((Invoke-AsmGit -Repo $Repo -GitArgs @('remote', 'get-url', 'origin') -AllowFail).ExitCode -eq 0)
}

function Get-AsmRepoDirtyPaths {
    param([string]$Repo)
    $o = (Invoke-AsmGit -Repo $Repo -GitArgs @('status', '--porcelain', '-uall')).Output
    if (-not $o) { return @() }
    return @($o -split "`n" | ForEach-Object { $_.Substring(3).Trim('"') })
}

function Assert-AsmRepoOnlyOurChanges {
    # 백업 저장소에 ASM이 만든 경로 외의 변경이 있으면 건드리지 않고 중단한다.
    param([string]$Repo)
    $foreign = @(Get-AsmRepoDirtyPaths $Repo | Where-Object { -not ($_.StartsWith('sessions/') -or $_ -eq 'manifest.json' -or $_ -eq '.asm-repo') })
    if ($foreign.Count -gt 0) {
        throw "백업 저장소에 ASM과 무관한 변경이 있어 중단합니다 (파일을 건드리지 않았습니다): $($foreign -join ', ')"
    }
}

function Get-AsmRepoPrivacy {
    # 'public' | 'private' | 'unknown'. 비로그인 GitHub API로 확인한다(비공개 저장소는 404).
    param([string]$Repo)
    $url = (Invoke-AsmGit -Repo $Repo -GitArgs @('remote', 'get-url', 'origin') -AllowFail).Output
    if ($url -notmatch 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?/?$') { return 'unknown' }
    $api = "https://api.github.com/repos/$($Matches[1])/$($Matches[2])"
    $code = $null
    try {
        $r = Invoke-WebRequest -Uri $api -UseBasicParsing -TimeoutSec 15 -Headers @{ 'User-Agent' = 'ai-session-manager' }
        $code = [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    }
    if ($code -eq 200) { return 'public' }
    if ($code -eq 404) { return 'private' }
    return 'unknown'
}

function Test-AsmRemoteBlobs {
    # 푸시 후 원격에 올라간 파일이 로컬과 동일한 Git blob인지 확인한다.
    param([string]$Repo, [string]$Branch, [string[]]$Paths)
    Invoke-AsmGit -Repo $Repo -GitArgs @('fetch', 'origin', $Branch) | Out-Null
    $res = @()
    foreach ($p in $Paths) {
        $remote = (Invoke-AsmGit -Repo $Repo -GitArgs @('rev-parse', "origin/${Branch}:$p") -AllowFail)
        $local = (Invoke-AsmGit -Repo $Repo -GitArgs @('hash-object', '--', $p)).Output
        $res += [pscustomobject]@{ Path = $p; Match = ($remote.ExitCode -eq 0 -and $remote.Output -eq $local) }
    }
    return $res
}

function Confirm-AsmAction {
    param([string]$Message, [switch]$Yes)
    if ($Yes) { return }
    $a = Read-Host "$Message 계속하려면 yes 입력"
    if ($a -ne 'yes') { throw '사용자가 취소했습니다.' }
}
