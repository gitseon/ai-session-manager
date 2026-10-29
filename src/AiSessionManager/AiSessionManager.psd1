@{
    RootModule            = 'AiSessionManager.psm1'
    ModuleVersion         = '0.1.0'
    GUID                  = '6f0d3b8e-3c1a-4a52-9d57-2b6a7c1e5f10'
    Author                = 'gitseon'
    Description           = 'Claude Code / Codex 세션 암호화 백업·복원 엔진'
    PowerShellVersion     = '5.1'
    FunctionsToExport     = @('Invoke-AsmDoctor', 'Invoke-AsmBackup', 'Invoke-AsmRestore', 'Get-AsmSessionList', 'Get-AsmStatus', 'Get-AsmVersionInfo', 'Initialize-Asm', 'New-AsmHandoff')
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
}
