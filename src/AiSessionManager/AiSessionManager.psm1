foreach ($dir in 'Private', 'Public') {
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $dir) -Filter '*.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }
}

Export-ModuleMember -Function Invoke-AsmDoctor, Invoke-AsmBackup, Invoke-AsmRestore, Get-AsmSessionList, Get-AsmStatus, Get-AsmVersionInfo, Initialize-Asm, New-AsmHandoff
