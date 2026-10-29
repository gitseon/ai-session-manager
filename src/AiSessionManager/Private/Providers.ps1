# Claude Code: <CLAUDE_CONFIG_DIR|~/.claude>/projects/<경로를 '-'로 치환한 폴더>/<세션UUID>.jsonl (+ 같은 이름의 폴더)
# Codex:       <CODEX_HOME|~/.codex>/sessions/YYYY/MM/DD/rollout-<시각>-<UUID>.jsonl
# 확인 상태는 docs/FORMATS.md 참고.

function Get-AsmClaudeHome {
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return (Join-AsmPath (Get-UserHome) @('.claude'))
}

function Get-AsmCodexHome {
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-AsmPath (Get-UserHome) @('.codex'))
}

function ConvertTo-AsmClaudeProjectDir {
    param([string]$Path)
    return [regex]::Replace($Path, '[^A-Za-z0-9]', '-')
}

function Read-AsmJsonlHead {
    param([string]$Path, [int]$MaxLines = 80)
    $objs = New-Object System.Collections.ArrayList
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
    try {
        $n = 0
        while ($n -lt $MaxLines) {
            $line = $sr.ReadLine()
            if ($null -eq $line) { break }
            $n++
            if (-not $line.Trim()) { continue }
            try { [void]$objs.Add(($line | ConvertFrom-Json)) } catch { }
        }
    } finally { $sr.Dispose() }
    return ,@($objs)
}

function Get-AsmTextFromContent {
    param($Content)
    if ($null -eq $Content) { return '' }
    if ($Content -is [string]) { return $Content }
    $parts = @()
    foreach ($c in @($Content)) {
        if ($c -is [string]) { $parts += $c }
        elseif ($c.text) { $parts += [string]$c.text }
    }
    return ($parts -join "`n")
}

function Test-AsmNoiseText {
    param([string]$Text)
    $t = $Text.TrimStart()
    foreach ($p in @('<system-reminder>', '<command-name>', '<command-message>', '<local-command', '<environment_context>', '<user_instructions>', '# AGENTS.md', 'Caveat:')) {
        if ($t.StartsWith($p)) { return $true }
    }
    return (-not $t)
}

function Get-AsmMessage {
    # 한 줄(JSON 객체)에서 사용자/어시스턴트 대화 텍스트를 뽑는다. 해당 없으면 $null.
    param([string]$Tool, $Obj)
    if ($Tool -eq 'claude') {
        if ($Obj.type -in @('user', 'assistant') -and $Obj.message -and -not $Obj.isMeta) {
            $text = Get-AsmTextFromContent $Obj.message.content
            if (-not (Test-AsmNoiseText $text)) { return @{ role = [string]$Obj.type; text = $text } }
        }
        return $null
    }
    $m = $null
    if ($Obj.type -eq 'response_item' -and $Obj.payload -and $Obj.payload.type -eq 'message') { $m = $Obj.payload }
    elseif ($Obj.type -eq 'message') { $m = $Obj }
    if ($m -and $m.role -in @('user', 'assistant')) {
        $text = Get-AsmTextFromContent $m.content
        if (-not (Test-AsmNoiseText $text)) { return @{ role = [string]$m.role; text = $text } }
    }
    return $null
}

function Get-AsmTitle {
    param([string]$Tool, $Head)
    foreach ($o in $Head) {
        $m = Get-AsmMessage -Tool $Tool -Obj $o
        if ($m -and $m.role -eq 'user') {
            $t = ($m.text -replace '\s+', ' ').Trim()
            if ($t.Length -gt 80) { $t = $t.Substring(0, 80) + '…' }
            return $t
        }
    }
    return ''
}

function Get-AsmClaudeSessions {
    $root = Get-AsmClaudeHome
    $proj = Join-AsmPath $root @('projects')
    if (-not (Test-Path -LiteralPath $proj)) { return @() }
    $list = @()
    foreach ($dir in Get-ChildItem -LiteralPath $proj -Directory) {
        foreach ($f in Get-ChildItem -LiteralPath $dir.FullName -Filter '*.jsonl' -File) {
            if ($f.BaseName -notmatch '^[0-9a-fA-F\-]{36}$') { continue }
            $head = Read-AsmJsonlHead $f.FullName
            $cwd = ''
            $started = $null
            foreach ($o in $head) {
                if (-not $cwd -and $o.cwd) { $cwd = [string]$o.cwd }
                if (-not $started -and $o.timestamp) { $started = [string]$o.timestamp }
            }
            $list += [pscustomobject]@{
                Tool = 'claude'; Id = $f.BaseName; Cwd = $cwd; Title = (Get-AsmTitle 'claude' $head)
                Started = $started; Modified = $f.LastWriteTimeUtc; Root = $root
                MainRel = "projects/$($dir.Name)/$($f.Name)"
                CompanionRel = "projects/$($dir.Name)/$($f.BaseName)"
            }
        }
    }
    return $list
}

function Get-AsmCodexSessions {
    $root = Get-AsmCodexHome
    $sd = Join-AsmPath $root @('sessions')
    if (-not (Test-Path -LiteralPath $sd)) { return @() }
    $list = @()
    foreach ($f in Get-ChildItem -LiteralPath $sd -Recurse -Filter 'rollout-*.jsonl' -File) {
        $head = Read-AsmJsonlHead $f.FullName
        $id = ''
        $cwd = ''
        $started = $null
        foreach ($o in $head) {
            $meta = $null
            if ($o.type -eq 'session_meta' -and $o.payload) { $meta = $o.payload }
            elseif ($o.id -and -not $o.type) { $meta = $o }
            if ($meta) {
                if (-not $id -and $meta.id) { $id = [string]$meta.id }
                if (-not $cwd -and $meta.cwd) { $cwd = [string]$meta.cwd }
                if (-not $started -and $meta.timestamp) { $started = [string]$meta.timestamp }
            }
            if (-not $cwd -and $o.payload -and $o.payload.cwd) { $cwd = [string]$o.payload.cwd }
        }
        if (-not $id -and $f.BaseName -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$') { $id = $Matches[1] }
        if (-not $id) { continue }
        $list += [pscustomobject]@{
            Tool = 'codex'; Id = $id; Cwd = $cwd; Title = (Get-AsmTitle 'codex' $head)
            Started = $started; Modified = $f.LastWriteTimeUtc; Root = $root
            MainRel = (Get-AsmRelativePath $root $f.FullName); CompanionRel = $null
        }
    }
    return $list
}

function Get-AsmLocalSessions {
    param([ValidateSet('all', 'claude', 'codex')][string]$Tool = 'all')
    $r = @()
    if ($Tool -in @('all', 'claude')) { $r += Get-AsmClaudeSessions }
    if ($Tool -in @('all', 'codex')) { $r += Get-AsmCodexSessions }
    return @($r)
}

function Get-AsmSessionFiles {
    # 세션 하나를 구성하는 파일(본문 + Claude의 동반 폴더). 인증 파일 제외 여부는 호출자가 판단한다.
    param($Session)
    $files = @()
    $main = Join-AsmPath $Session.Root @($Session.MainRel -split '/')
    $fi = Get-Item -LiteralPath $main
    $files += [pscustomobject]@{ Rel = $Session.MainRel; Full = $fi.FullName; Length = $fi.Length }
    if ($Session.CompanionRel) {
        $cd = Join-AsmPath $Session.Root @($Session.CompanionRel -split '/')
        if (Test-Path -LiteralPath $cd -PathType Container) {
            foreach ($f in Get-ChildItem -LiteralPath $cd -Recurse -File) {
                $files += [pscustomobject]@{ Rel = (Get-AsmRelativePath $Session.Root $f.FullName); Full = $f.FullName; Length = $f.Length }
            }
        }
    }
    return $files
}

function Get-AsmFingerprint {
    param([object[]]$Files)
    $lines = @($Files | Sort-Object Rel | ForEach-Object { "$($_.Rel):$(Get-AsmFileSha256 $_.Full)" })
    return (Get-AsmBytesSha256 ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))
}

function Select-AsmSessions {
    param([object[]]$Sessions, [string[]]$Id, [int]$Latest = 0, [string]$Project)
    $r = @($Sessions)
    if ($Project) {
        $p = $Project.TrimEnd('\', '/')
        $r = @($r | Where-Object { $_.Cwd -and ($_.Cwd.TrimEnd('\', '/') -ieq $p) })
    }
    if ($Id) {
        $picked = @()
        foreach ($i in $Id) {
            if ($i.Length -lt 6) { throw "세션 ID는 6자 이상 입력하세요: $i" }
            $m = @($r | Where-Object { $_.Id -eq $i -or $_.Id.StartsWith($i, [StringComparison]::OrdinalIgnoreCase) })
            if ($m.Count -eq 0) { throw "세션을 찾을 수 없습니다: $i" }
            if ($m.Count -gt 1) { throw "ID가 모호합니다. 더 길게 입력하세요: $i" }
            $picked += $m[0]
        }
        $r = $picked
    }
    if ($Latest -gt 0) { $r = @($r | Sort-Object Modified -Descending | Select-Object -First $Latest) }
    return $r
}

function Assert-AsmSafeRel {
    # 백업 파일 안의 경로가 홈 밖으로 나가지 못하게 막는다.
    param([string]$Tool, [string]$Rel)
    $prefix = if ($Tool -eq 'claude') { 'projects/' } else { 'sessions/' }
    if (-not $Rel.StartsWith($prefix) -or $Rel -match '(^|/)\.\.(/|$)' -or $Rel -match '^[/\\]' -or $Rel -match ':') {
        throw "허용되지 않는 복원 경로입니다: $Rel"
    }
}
