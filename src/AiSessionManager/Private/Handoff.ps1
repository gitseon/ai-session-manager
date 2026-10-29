function Get-AsmMessagesFromBytes {
    param([string]$Tool, [byte[]]$Bytes)
    $text = [Text.Encoding]::UTF8.GetString($Bytes)
    $msgs = @()
    foreach ($line in ($text -split "`n")) {
        if (-not $line.Trim()) { continue }
        try { $o = $line | ConvertFrom-Json } catch { continue }
        $m = Get-AsmMessage -Tool $Tool -Obj $o
        if ($m) { $msgs += , $m }
    }
    return $msgs
}

function ConvertTo-AsmHandoffText {
    param($Meta, [object[]]$Messages, [int]$Last = 12, [int]$MaxChars = 1500)
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("# 작업 인수인계: $($Meta.tool) 세션 $($Meta.id)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> 원래 대화를 이어 갈 수 없을 때 새 세션에 붙여 넣는 요약이다. 아래 내용은 이전 대화 기록에서 자동 추출한 것이며 정확성은 검증되지 않았다.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 세션 정보')
    [void]$sb.AppendLine("- 도구: $($Meta.tool)")
    [void]$sb.AppendLine("- 작업 폴더(원래 PC): $($Meta.cwd)")
    [void]$sb.AppendLine("- 시작: $($Meta.started)")
    [void]$sb.AppendLine("- 마지막 수정: $($Meta.modified)")
    [void]$sb.AppendLine("- 백업 시각: $($Meta.backedUpAt)")
    $gs = $Meta.gitState
    if ($gs) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## 백업 시점의 Git 작업 상태')
        [void]$sb.AppendLine("- 브랜치: $($gs.branch)")
        [void]$sb.AppendLine("- 커밋: $($gs.head)")
        if ($gs.remote) { [void]$sb.AppendLine("- 원격: $($gs.remote)") }
        $d = @($gs.dirty)
        if ($d.Count -gt 0) {
            [void]$sb.AppendLine("- 커밋되지 않은 변경 ($($d.Count)개 이하 표시):")
            foreach ($x in $d) { [void]$sb.AppendLine("  - ``$x``") }
        } else {
            [void]$sb.AppendLine('- 커밋되지 않은 변경 없음')
        }
        if ($gs.diffStat) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('```')
            [void]$sb.AppendLine([string]$gs.diffStat)
            [void]$sb.AppendLine('```')
        }
    }
    $msgs = @($Messages)
    $firstUser = $msgs | Where-Object { $_.role -eq 'user' } | Select-Object -First 1
    if ($firstUser) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## 최초 요청')
        [void]$sb.AppendLine((Limit-AsmText $firstUser.text $MaxChars))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## 마지막 대화 (최대 $Last 개)")
    foreach ($m in ($msgs | Select-Object -Last $Last)) {
        $who = if ($m.role -eq 'user') { '사용자' } else { 'AI' }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("### $who")
        [void]$sb.AppendLine((Limit-AsmText $m.text $MaxChars))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 새 세션에 붙여 넣을 안내문')
    [void]$sb.AppendLine('위 인수인계 문서를 읽고, 현재 저장소의 실제 상태(git status, 최근 커밋)를 먼저 확인한 뒤, 마지막 대화에서 중단된 지점부터 이어서 작업해 줘. 문서와 실제 상태가 다르면 실제 상태를 기준으로 하고 나에게 알려 줘.')
    return $sb.ToString()
}

function Limit-AsmText {
    param([string]$Text, [int]$Max)
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max) + "`n…(생략)"
}
