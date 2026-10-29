# 형식: "ASM1"(4) | 반복횟수 int32 BE(4) | salt(16) | iv(16) | AES-256-CBC 암호문 | HMAC-SHA256(32)
# 암호화 후 MAC(encrypt-then-MAC). 키는 비밀번호에서 PBKDF2-SHA256으로 매번 유도하며 어디에도 저장하지 않는다.
# AES-GCM은 Windows PowerShell 5.1(.NET Framework)에 없어 CBC+HMAC를 쓴다.

$script:AsmMagic = [Text.Encoding]::ASCII.GetBytes('ASM1')

function New-AsmRandomBytes {
    param([int]$Count)
    $b = New-Object byte[] $Count
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return ,$b
}

function Get-AsmKeys {
    param([string]$Passphrase, [byte[]]$Salt, [int]$Iterations)
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes -ArgumentList $Passphrase, $Salt, $Iterations, ([Security.Cryptography.HashAlgorithmName]::SHA256)
    try { $raw = $kdf.GetBytes(64) } finally { $kdf.Dispose() }
    $enc = New-Object byte[] 32
    $mac = New-Object byte[] 32
    [Array]::Copy($raw, 0, $enc, 0, 32)
    [Array]::Copy($raw, 32, $mac, 0, 32)
    return @{ Enc = $enc; Mac = $mac }
}

function Get-AsmHmac {
    param([byte[]]$Key, [byte[]]$Data, [int]$Length)
    $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, $Key)
    try { return ,$h.ComputeHash($Data, 0, $Length) } finally { $h.Dispose() }
}

function Test-AsmBytesEqual {
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    $d = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $d = $d -bor ($A[$i] -bxor $B[$i]) }
    return ($d -eq 0)
}

function Protect-AsmBytes {
    param([byte[]]$Plain, [string]$Passphrase, [int]$Iterations = 0)
    if (-not $Passphrase) { throw '비밀번호가 비어 있습니다.' }
    if ($Iterations -le 0) { $Iterations = Get-AsmKdfIterations }
    $salt = New-AsmRandomBytes 16
    $iv = New-AsmRandomBytes 16
    $keys = Get-AsmKeys -Passphrase $Passphrase -Salt $salt -Iterations $Iterations
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $keys.Enc
        $aes.IV = $iv
        $enc = $aes.CreateEncryptor()
        $ct = $enc.TransformFinalBlock($Plain, 0, $Plain.Length)
    } finally { $aes.Dispose() }
    $iter = [BitConverter]::GetBytes([int32]$Iterations)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($iter) }
    $ms = New-Object IO.MemoryStream
    foreach ($part in @($script:AsmMagic, $iter, $salt, $iv, $ct)) { $ms.Write($part, 0, $part.Length) }
    $body = $ms.ToArray()
    $mac = Get-AsmHmac -Key $keys.Mac -Data $body -Length $body.Length
    $out = New-Object byte[] ($body.Length + 32)
    [Array]::Copy($body, 0, $out, 0, $body.Length)
    [Array]::Copy($mac, 0, $out, $body.Length, 32)
    return ,$out
}

function Unprotect-AsmBytes {
    param([byte[]]$Blob, [string]$Passphrase)
    if ($Blob.Length -lt 88) { throw '암호화 파일이 너무 짧거나 손상되었습니다.' }
    for ($i = 0; $i -lt 4; $i++) {
        if ($Blob[$i] -ne $script:AsmMagic[$i]) { throw 'ASM 암호화 파일이 아닙니다.' }
    }
    $ib = New-Object byte[] 4
    [Array]::Copy($Blob, 4, $ib, 0, 4)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($ib) }
    $iterations = [BitConverter]::ToInt32($ib, 0)
    if ($iterations -lt 1000 -or $iterations -gt 5000000) { throw '암호화 파일의 KDF 반복 횟수가 허용 범위를 벗어났습니다.' }
    $salt = New-Object byte[] 16
    $iv = New-Object byte[] 16
    [Array]::Copy($Blob, 8, $salt, 0, 16)
    [Array]::Copy($Blob, 24, $iv, 0, 16)
    $bodyLen = $Blob.Length - 32
    $ctLen = $bodyLen - 40
    if ($ctLen -le 0 -or ($ctLen % 16) -ne 0) { throw '암호문 길이가 올바르지 않습니다.' }
    $keys = Get-AsmKeys -Passphrase $Passphrase -Salt $salt -Iterations $iterations
    $expected = Get-AsmHmac -Key $keys.Mac -Data $Blob -Length $bodyLen
    $actual = New-Object byte[] 32
    [Array]::Copy($Blob, $bodyLen, $actual, 0, 32)
    if (-not (Test-AsmBytesEqual $expected $actual)) {
        throw '복호화 실패: 비밀번호가 틀렸거나 파일이 변조·손상되었습니다.'
    }
    $ct = New-Object byte[] $ctLen
    [Array]::Copy($Blob, 40, $ct, 0, $ctLen)
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $keys.Enc
        $aes.IV = $iv
        $dec = $aes.CreateDecryptor()
        return ,$dec.TransformFinalBlock($ct, 0, $ct.Length)
    } finally { $aes.Dispose() }
}

function Get-AsmPassphrase {
    param([switch]$Confirm)
    if ($env:ASM_PASSPHRASE) { return $env:ASM_PASSPHRASE }
    $s1 = Read-Host -AsSecureString '세션 암호화 비밀번호'
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
    if ($Confirm) {
        $s2 = Read-Host -AsSecureString '비밀번호 확인'
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
        if ($p1 -ne $p2) { throw '비밀번호가 일치하지 않습니다.' }
    }
    if (-not $p1) { throw '비밀번호가 비어 있습니다.' }
    return $p1
}

function Compress-AsmBytes {
    param([byte[]]$Bytes)
    $out = New-Object IO.MemoryStream
    $gz = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionMode]::Compress, $true)
    $gz.Write($Bytes, 0, $Bytes.Length)
    $gz.Dispose()
    return ,$out.ToArray()
}

function Expand-AsmBytes {
    param([byte[]]$Bytes)
    $in = New-Object IO.MemoryStream(, $Bytes)
    $out = New-Object IO.MemoryStream
    $gz = New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
    try { $gz.CopyTo($out) } finally { $gz.Dispose() }
    return ,$out.ToArray()
}

# 패키지: int32 BE 메타 길이 | 메타 JSON(UTF-8, 파일 목록 포함) | 파일 바이트 연속. 전체를 gzip.
# 큰 바이너리를 JSON에 넣지 않는다(Windows PowerShell 5.1의 ConvertFrom-Json 2MB 제한 회피).
function ConvertTo-AsmPackage {
    param([hashtable]$Meta, [object[]]$Files)
    $table = @()
    $datas = @()
    foreach ($f in $Files) {
        $bytes = Read-AsmFileBytes $f.Full
        $table += @{ path = $f.Rel; size = $bytes.Length; sha256 = (Get-AsmBytesSha256 $bytes) }
        $datas += , $bytes
    }
    $m = @{}
    foreach ($k in $Meta.Keys) { $m[$k] = $Meta[$k] }
    $m['files'] = $table
    $metaBytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $m -Depth 6 -Compress))
    $len = [BitConverter]::GetBytes([int32]$metaBytes.Length)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($len) }
    $ms = New-Object IO.MemoryStream
    $ms.Write($len, 0, 4)
    $ms.Write($metaBytes, 0, $metaBytes.Length)
    foreach ($d in $datas) { $ms.Write($d, 0, $d.Length) }
    return ,(Compress-AsmBytes $ms.ToArray())
}

function ConvertFrom-AsmPackage {
    param([byte[]]$Package)
    $raw = Expand-AsmBytes $Package
    $lb = New-Object byte[] 4
    [Array]::Copy($raw, 0, $lb, 0, 4)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($lb) }
    $metaLen = [BitConverter]::ToInt32($lb, 0)
    if ($metaLen -le 0 -or $metaLen -gt ($raw.Length - 4)) { throw '패키지 메타 길이가 올바르지 않습니다.' }
    $meta = [Text.Encoding]::UTF8.GetString($raw, 4, $metaLen) | ConvertFrom-Json
    $off = 4 + $metaLen
    $files = @()
    foreach ($f in @($meta.files)) {
        $size = [int]$f.size
        if ($off + $size -gt $raw.Length) { throw "패키지가 잘렸습니다: $($f.path)" }
        $b = New-Object byte[] $size
        [Array]::Copy($raw, $off, $b, 0, $size)
        $off += $size
        if ((Get-AsmBytesSha256 $b) -ne $f.sha256) { throw "파일 무결성 검증 실패: $($f.path)" }
        $files += [pscustomobject]@{ Path = [string]$f.path; Bytes = $b; Sha256 = [string]$f.sha256 }
    }
    return [pscustomobject]@{ Meta = $meta; Files = $files }
}
