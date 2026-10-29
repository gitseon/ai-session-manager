# CI에서 Pester 5를 설치하고 tests/ 를 실행한다. PowerShell 7, Windows PowerShell 5.1 모두에서 동작한다.
$ErrorActionPreference = 'Stop'
Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Force -SkipPublisherCheck -Scope CurrentUser
Import-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99
Write-Host "PowerShell $($PSVersionTable.PSVersion) / Pester $((Get-Module Pester).Version)"
$c = New-PesterConfiguration
$c.Run.Path = './tests'
$c.Run.Exit = $true
$c.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $c
