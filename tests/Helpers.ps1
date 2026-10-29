# 테스트 전용 헬퍼. 실제 사용자 세션 폴더(~/.claude, ~/.codex)는 절대 건드리지 않고 TestDrive 안의 가짜 데이터만 쓴다.
$script:ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/AiSessionManager/AiSessionManager.psd1'

function Import-AsmForTest {
    Import-Module $script:ModulePath -Force
}

function Invoke-Private {
    param([scriptblock]$Script, [object[]]$Arguments = @())
    & (Get-Module AiSessionManager) $Script @Arguments
}

function New-TestDir {
    param([string]$Root, [string]$Name)
    $p = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    return $p
}

function New-FakeClaudeSession {
    param([string]$ClaudeHome, [string]$Cwd, [string]$Id, [string]$Prompt = 'hello task', [switch]$WithCompanion)
    $dirName = [regex]::Replace($Cwd, '[^A-Za-z0-9]', '-')
    $dir = Join-Path $ClaudeHome "projects/$dirName"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $lines = @(
        (@{ type = 'user'; cwd = $Cwd; sessionId = $Id; timestamp = '2026-01-01T00:00:00Z'; message = @{ role = 'user'; content = $Prompt } } | ConvertTo-Json -Compress -Depth 5),
        (@{ type = 'assistant'; timestamp = '2026-01-01T00:00:05Z'; message = @{ role = 'assistant'; content = @(@{ type = 'text'; text = 'working on it' }) } } | ConvertTo-Json -Compress -Depth 5),
        (@{ type = 'user'; message = @{ role = 'user'; content = 'second request' } } | ConvertTo-Json -Compress -Depth 5)
    )
    [IO.File]::WriteAllText((Join-Path $dir "$Id.jsonl"), (($lines -join "`n") + "`n"))
    if ($WithCompanion) {
        New-Item -ItemType Directory -Path (Join-Path $dir "$Id/tool-results") -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir "$Id/tool-results/out.txt"), 'tool output')
        [IO.File]::WriteAllText((Join-Path $dir "$Id/tool-results/oauth-token.json"), '{"note":"must never be backed up"}')
    }
    return (Join-Path $dir "$Id.jsonl")
}

function New-FakeCodexSession {
    param([string]$CodexHome, [string]$Cwd, [string]$Id, [string]$Prompt = 'fix the bug')
    $dir = Join-Path $CodexHome 'sessions/2026/01/02'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $lines = @(
        (@{ timestamp = '2026-01-02T00:00:00Z'; type = 'session_meta'; payload = @{ id = $Id; timestamp = '2026-01-02T00:00:00Z'; cwd = $Cwd } } | ConvertTo-Json -Compress -Depth 5),
        (@{ type = 'response_item'; payload = @{ type = 'message'; role = 'user'; content = @(@{ type = 'input_text'; text = $Prompt }) } } | ConvertTo-Json -Compress -Depth 6),
        (@{ type = 'response_item'; payload = @{ type = 'message'; role = 'assistant'; content = @(@{ type = 'output_text'; text = 'fixed it' }) } } | ConvertTo-Json -Compress -Depth 6)
    )
    $f = Join-Path $dir "rollout-2026-01-02T00-00-00-$Id.jsonl"
    [IO.File]::WriteAllText($f, (($lines -join "`n") + "`n"))
    return $f
}

function Set-TestGitIdentity {
    $env:GIT_AUTHOR_NAME = 'asm-test'; $env:GIT_AUTHOR_EMAIL = 'asm-test@example.invalid'
    $env:GIT_COMMITTER_NAME = 'asm-test'; $env:GIT_COMMITTER_EMAIL = 'asm-test@example.invalid'
}
