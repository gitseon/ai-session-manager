$script:AsmVersion = '0.1.0'

function Get-UserHome {
    if ($HOME) { return $HOME }
    return $env:USERPROFILE
}

function Join-AsmPath {
    param([string]$Base, [string[]]$Parts)
    $p = $Base
    foreach ($x in $Parts) { $p = [IO.Path]::Combine($p, $x) }
    return $p
}

function Get-AsmHome {
    if ($env:ASM_HOME) { return $env:ASM_HOME }
    return (Join-AsmPath (Get-UserHome) @('.asm'))
}

function Get-AsmConfigPath {
    return (Join-AsmPath (Get-AsmHome) @('config.json'))
}

function Write-AsmUtf8 {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Read-AsmFileBytes {
    # 실행 중인 CLI가 열어 둔 파일도 읽을 수 있도록 공유 모드로 연다.
    param([string]$Path)
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $buf = New-Object byte[] ([int]$fs.Length)
        $off = 0
        while ($off -lt $buf.Length) {
            $n = $fs.Read($buf, $off, $buf.Length - $off)
            if ($n -le 0) { break }
            $off += $n
        }
        if ($off -ne $buf.Length) { $buf = $buf[0..($off - 1)] }
        return ,$buf
    } finally { $fs.Dispose() }
}

function Get-AsmBytesSha256 {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $h = $sha.ComputeHash($Bytes)
        return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $sha.Dispose() }
}

function Get-AsmFileSha256 {
    param([string]$Path)
    return (Get-AsmBytesSha256 (Read-AsmFileBytes $Path))
}

function Get-AsmRelativePath {
    param([string]$Base, [string]$Full)
    $b = $Base.TrimEnd('\', '/')
    $rel = $Full.Substring($b.Length).TrimStart('\', '/')
    return ($rel -replace '\\', '/')
}

function Get-AsmConfig {
    $p = Get-AsmConfigPath
    if (Test-Path -LiteralPath $p) {
        return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return [pscustomobject]@{ backupRepo = $null }
}

function Set-AsmConfigValue {
    param([string]$Name, $Value)
    $c = Get-AsmConfig
    if ($c.PSObject.Properties[$Name]) { $c.$Name = $Value }
    else { Add-Member -InputObject $c -NotePropertyName $Name -NotePropertyValue $Value }
    Write-AsmUtf8 (Get-AsmConfigPath) (ConvertTo-Json -InputObject $c -Depth 4)
}

function Get-AsmBackupRepo {
    $c = Get-AsmConfig
    if (-not $c.backupRepo) {
        throw '백업 저장소가 설정되지 않았습니다. 먼저 실행하세요: asm init -Repo <비공개 저장소 로컬 경로>'
    }
    if (-not (Test-Path -LiteralPath (Join-AsmPath $c.backupRepo @('.git')))) {
        throw "백업 저장소 경로가 Git 저장소가 아닙니다: $($c.backupRepo)"
    }
    return [string]$c.backupRepo
}

function Invoke-AsmGit {
    param([string]$Repo, [string[]]$GitArgs, [switch]$AllowFail)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & git -C $Repo @GitArgs 2>&1 } finally { $ErrorActionPreference = $old }
    $code = $LASTEXITCODE
    $text = (($out | ForEach-Object { $_.ToString() }) -join "`n").Trim()
    if ($code -ne 0 -and -not $AllowFail) {
        throw "git $($GitArgs -join ' ') 실패 (코드 $code): $text"
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $text }
}

function Get-AsmKdfIterations {
    $n = 200000
    if ($env:ASM_KDF_ITERATIONS) {
        $v = 0
        if ([int]::TryParse($env:ASM_KDF_ITERATIONS, [ref]$v) -and $v -ge 1000) { $n = $v }
    }
    return $n
}

function Get-AsmGitState {
    # 작업 상태 인수인계용. 원격 URL의 인증정보는 제거한다.
    param([string]$Cwd)
    if (-not $Cwd -or -not (Test-Path -LiteralPath $Cwd)) { return $null }
    $r = Invoke-AsmGit -Repo $Cwd -GitArgs @('rev-parse', '--is-inside-work-tree') -AllowFail
    if ($r.ExitCode -ne 0) { return $null }
    $branch = (Invoke-AsmGit -Repo $Cwd -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD') -AllowFail).Output
    $head = (Invoke-AsmGit -Repo $Cwd -GitArgs @('rev-parse', 'HEAD') -AllowFail).Output
    $st = (Invoke-AsmGit -Repo $Cwd -GitArgs @('status', '--porcelain') -AllowFail).Output
    $dirty = @()
    if ($st) { $dirty = @($st -split "`n" | Select-Object -First 30) }
    $remote = (Invoke-AsmGit -Repo $Cwd -GitArgs @('remote', 'get-url', 'origin') -AllowFail).Output
    $remote = $remote -replace '://[^@/]+@', '://'
    $stat = (Invoke-AsmGit -Repo $Cwd -GitArgs @('diff', '--stat', 'HEAD') -AllowFail).Output
    return @{
        branch    = $branch
        head      = $head
        dirty     = $dirty
        remote    = $remote
        diffStat  = $stat
    }
}
