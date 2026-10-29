<#
.SYNOPSIS
asm - Claude Code / Codex 세션 백업·복원 CLI
.EXAMPLE
asm doctor
asm list
asm backup -Latest 1            # 계획만 출력
asm backup -Latest 1 -Push      # 암호화 + 커밋 + 푸시 + 원격 검증
asm restore -Session <ID> -Apply
#>
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [string[]]$Session, [ValidateSet('all', 'claude', 'codex')][string]$Tool = 'all',
    [int]$Latest, [string]$Project, [string]$ProjectPath, [string]$Repo, [string]$Clone, [string]$Out,
    [switch]$All, [switch]$Apply, [switch]$Push, [switch]$Yes, [switch]$AllowSecrets, [switch]$Overwrite,
    [switch]$Pull, [switch]$Handoff, [switch]$Remote, [switch]$Decrypt, [switch]$Json
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\AiSessionManager\AiSessionManager.psd1') -Force

$map = @{
    doctor  = 'Invoke-AsmDoctor'; backup = 'Invoke-AsmBackup'; restore = 'Invoke-AsmRestore'
    list    = 'Get-AsmSessionList'; status = 'Get-AsmStatus'; version = 'Get-AsmVersionInfo'
    init    = 'Initialize-Asm'; handoff = 'New-AsmHandoff'
}
if (-not $map.ContainsKey($Command.ToLower())) {
    Write-Host '사용법: asm <doctor|backup|restore|list|status|version|init|handoff> [옵션]'
    Write-Host '자세한 내용: docs/USAGE.md'
    exit 0
}
$cmd = Get-Command $map[$Command.ToLower()]
$splat = @{}
foreach ($k in $PSBoundParameters.Keys) {
    if ($k -ne 'Command' -and $cmd.Parameters.ContainsKey($k)) { $splat[$k] = $PSBoundParameters[$k] }
}
try {
    $res = & $cmd @splat
    $code = 0
    if ($Command -eq 'doctor' -and @($res | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0) { $code = 1 }
    if ($Command -eq 'backup' -and $res.Mode -eq 'pushed' -and -not $res.RemoteVerified) { $code = 2 }
    if ($Json) { $res | ConvertTo-Json -Depth 6 }
    else {
        switch ($Command.ToLower()) {
            'backup' {
                Write-Host "모드: $($res.Mode)  저장소: $($res.Repo)"
                $res.Items | Select-Object Tool, Id, Status, FileCount, SizeBytes, Title | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
                foreach ($i in $res.Items) {
                    if ($i.SecretHits.Count) { Write-Host "[주의] $($i.Id): 비밀값 의심 패턴 → $($i.SecretHits -join ', ') (값은 표시하지 않음)" }
                    if ($i.SkippedFiles.Count) { Write-Host "[제외] $($i.Id): 인증 관련 파일 $($i.SkippedFiles.Count)개 제외" }
                }
                if ($res.Mode -eq 'plan') { Write-Host '계획만 출력했습니다. 실제 저장: -Apply, 커밋·푸시까지: -Push' }
                if ($res.Pushed) { Write-Host "푸시 완료: $($res.Commit)  원격 검증: $(if ($res.RemoteVerified) { '일치' } else { '불일치!' })" }
            }
            'restore' {
                foreach ($x in $res) {
                    Write-Host "== $($x.Tool) $($x.Id)  모드: $($x.Mode)"
                    if ($x.HandoffPath) { Write-Host "인수인계 문서: $($x.HandoffPath)" }
                    $x.Files | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
                    if ($x.Verify) { $x.Verify | Format-Table -AutoSize | Out-String -Width 200 | Write-Host }
                    if ($x.Conflicts -gt 0 -and $x.Mode -ne 'applied') { Write-Host "충돌 $($x.Conflicts)건: 기존 파일을 덮어쓰지 않았습니다. 덮어쓰려면 -Overwrite (기존 파일은 백업됩니다)." }
                    if ($x.Resume) { Write-Host "재개 명령: $($x.Resume)" }
                    if ($x.Mode -eq 'plan') { Write-Host '계획만 출력했습니다. 실제 복원: -Apply' }
                }
            }
            default { $res | Format-Table -AutoSize | Out-String -Width 200 | Write-Host }
        }
    }
    exit $code
} catch {
    Write-Host "오류: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
