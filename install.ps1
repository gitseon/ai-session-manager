<#
.SYNOPSIS
ai-session-manager 설치 (Windows PowerShell 5.1 / PowerShell 7).
.DESCRIPTION
기본 동작은 계획 출력 후 확인(yes)을 받는다. 기존 설치 폴더는 삭제하지 않고 .bak-<시각> 으로 옮긴다.
-AddToPath  사용자 PATH에 bin 폴더를 추가한다.
-InstallSkill  스킬 폴더(SKILL.md)를 ~/.claude/skills, ~/.codex/skills 에 복사한다(이미 있으면 건드리지 않음, -Force 시 .bak 으로 이동 후 설치).
#>
[CmdletBinding()]
param(
    [string]$Destination,
    [switch]$AddToPath,
    [switch]$InstallSkill,
    [switch]$Force,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
if (-not $Destination) {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $HOME '.local/share' }
    $Destination = Join-Path $base 'ai-session-manager'
}
Write-Host "설치 계획"
Write-Host "  원본:   $src"
Write-Host "  대상:   $Destination"
if (Test-Path -LiteralPath $Destination) { Write-Host '  기존 설치 폴더는 삭제하지 않고 .bak-<시각> 으로 이동합니다.' }
if ($AddToPath) { Write-Host "  사용자 PATH에 추가: $(Join-Path $Destination 'bin')" }
if ($InstallSkill) { Write-Host '  스킬 설치: ~/.claude/skills, ~/.codex/skills (해당 도구 폴더가 있을 때만)' }
if (-not $Yes) {
    if ((Read-Host '계속하려면 yes 입력') -ne 'yes') { Write-Host '취소했습니다.'; exit 1 }
}

if (Test-Path -LiteralPath $Destination) {
    $bak = "$Destination.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Move-Item -LiteralPath $Destination -Destination $bak
    Write-Host "기존 설치를 이동했습니다: $bak"
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
foreach ($d in 'bin', 'src', 'skills') { Copy-Item -LiteralPath (Join-Path $src $d) -Destination $Destination -Recurse }
Write-Host "설치 완료: $Destination"

if ($AddToPath) {
    $bin = Join-Path $Destination 'bin'
    $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($cur -split ';') -notcontains $bin) {
        [Environment]::SetEnvironmentVariable('Path', ($cur.TrimEnd(';') + ';' + $bin), 'User')
        Write-Host 'PATH에 추가했습니다. 새 터미널을 여세요.'
    }
}
if ($InstallSkill) {
    foreach ($t in @(@('.claude', 'Claude Code'), @('.codex', 'Codex'))) {
        $toolHome = Join-Path $HOME $t[0]
        if (-not (Test-Path -LiteralPath $toolHome)) { Write-Host "$($t[1]): $toolHome 없음, 건너뜀"; continue }
        $target = Join-Path (Join-Path $toolHome 'skills') 'ai-session-manager'
        if (Test-Path -LiteralPath $target) {
            if (-not $Force) { Write-Host "$($t[1]): 이미 있음, 건드리지 않음 (-Force 로 교체)"; continue }
            Move-Item -LiteralPath $target -Destination "$target.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $src 'skills/ai-session-manager') -Destination $target -Recurse
        Write-Host "$($t[1]): 스킬 설치 $target"
    }
}
Write-Host '다음: asm doctor'
