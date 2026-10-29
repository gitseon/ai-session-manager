# 업로드 금지 파일(인증정보·키)과 세션 내용 속 비밀값 탐지. 탐지 결과는 패턴 이름만 보고하고 값은 출력하지 않는다.

$script:AsmForbiddenLeaf = '^(\.credentials\.json|auth\.json|\.env(\..*)?|.*\.(pem|key|p12|pfx|ppk)|id_(rsa|ed25519|ecdsa|dsa).*|.*oauth.*|.*token.*|.*secret.*|.*credential.*)$'

$script:AsmSecretPatterns = [ordered]@{
    'GitHub 토큰'          = 'gh[pousr]_[A-Za-z0-9]{36,}'
    'GitHub fine-grained'  = 'github_pat_[A-Za-z0-9_]{50,}'
    'Anthropic API 키'     = 'sk-ant-[A-Za-z0-9_\-]{20,}'
    'OpenAI API 키'        = 'sk-(proj-)?[A-Za-z0-9_\-]{32,}'
    'AWS 액세스 키'        = 'AKIA[0-9A-Z]{16}'
    '개인키 블록'          = '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
    'Slack 토큰'           = 'xox[baprs]-[A-Za-z0-9\-]{10,}'
    'Google API 키'        = 'AIza[0-9A-Za-z_\-]{35}'
    'OAuth JWT 토큰'       = '"(access|refresh|id)_token"\s*:\s*"eyJ'
    '서명된 다운로드 URL'  = 'X-Amz-Signature=[0-9a-f]{20,}'
}

function Test-AsmForbiddenPath {
    param([string]$Rel)
    $leaf = ($Rel -split '/')[-1]
    return ($leaf -imatch $script:AsmForbiddenLeaf)
}

function Test-AsmSecretText {
    param([string]$Text)
    $hits = @()
    foreach ($k in $script:AsmSecretPatterns.Keys) {
        if ([regex]::IsMatch($Text, $script:AsmSecretPatterns[$k])) { $hits += $k }
    }
    return $hits
}

function Test-AsmSecretBytes {
    param([byte[]]$Bytes)
    return (Test-AsmSecretText ([Text.Encoding]::UTF8.GetString($Bytes)))
}
