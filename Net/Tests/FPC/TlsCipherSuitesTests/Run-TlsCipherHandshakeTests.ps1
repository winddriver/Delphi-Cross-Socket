param(
    [string]$TestExe = (Join-Path $PSScriptRoot 'bin\x86_64-win64-openssl\TlsCipherSuitesTests.exe'),
    [string]$OpenSslExe = (Join-Path $PSScriptRoot '..\..\..\Tools\OpenSSL\openssl.exe'),
    [string]$LibSsl = (Join-Path $PSScriptRoot '..\..\..\Tools\OpenSSL\libssl-3-x64.dll'),
    [string]$LibCrypto = (Join-Path $PSScriptRoot '..\..\..\Tools\OpenSSL\libcrypto-3-x64.dll')
)

$ErrorActionPreference = 'Stop'
$runRoot = Join-Path $PSScriptRoot ('bin\handshake-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot | Out-Null
$TestExe = (Resolve-Path -LiteralPath $TestExe).Path
$OpenSslExe = (Resolve-Path -LiteralPath $OpenSslExe).Path
if ($LibSsl) { $LibSsl = (Resolve-Path -LiteralPath $LibSsl).Path }
if ($LibCrypto) { $LibCrypto = (Resolve-Path -LiteralPath $LibCrypto).Path }

function Start-TestProcess([string]$File, [string[]]$Arguments) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $File
    $startInfo.WorkingDirectory = $runRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    if ($LibSsl) { $startInfo.Environment['CROSS_SOCKET_TEST_LIBSSL'] = $LibSsl }
    if ($LibCrypto) { $startInfo.Environment['CROSS_SOCKET_TEST_LIBCRYPTO'] = $LibCrypto }
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $startInfo
    if (-not $child.Start()) { throw "无法启动 $File" }
    return $child
}

function Stop-TestProcess($Child) {
    if ($null -ne $Child) {
        if (-not $Child.HasExited) { $Child.Kill(); $Child.WaitForExit() }
        $Child.Dispose()
    }
}

function New-TestPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}

# 只生成本次本地测试的证书配置，不访问或修改任何全局配置。
$certConfig = Join-Path $runRoot 'certificate.cnf'
@'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = localhost
[extensions]
subjectAltName = DNS:localhost
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign
'@ | Set-Content -LiteralPath $certConfig -Encoding ascii

foreach ($kind in 'rsa','ecdsa') {
    $keyArguments = if ($kind -eq 'rsa') { @('-newkey','rsa:2048') }
                    else { @('-newkey','ec','-pkeyopt','ec_paramgen_curve:P-256') }
    $certificate = Join-Path $runRoot "$kind-cert.pem"
    $privateKey = Join-Path $runRoot "$kind-key.pem"
    & $OpenSslExe req -x509 @keyArguments -nodes -days 1 -config $certConfig `
        -keyout $privateKey -out $certificate 2> (Join-Path $runRoot "$kind-generation.log")
    if ($LASTEXITCODE -ne 0) { throw "$kind 测试证书生成失败" }
}

$default12 = @('ECDHE-RSA-AES128-GCM-SHA256','ECDHE-ECDSA-AES128-GCM-SHA256',
    'ECDHE-RSA-CHACHA20-POLY1305','ECDHE-ECDSA-CHACHA20-POLY1305',
    'ECDHE-RSA-AES256-GCM-SHA384','ECDHE-ECDSA-AES256-GCM-SHA384')
$default13 = @('TLS_AES_256_GCM_SHA384','TLS_CHACHA20_POLY1305_SHA256','TLS_AES_128_GCM_SHA256')
$cases = @()
foreach ($cipher in $default12) { $cases += @{ Version='TLSv1.2'; Cipher=$cipher; C12='default'; C13='default'; Expected=$cipher } }
foreach ($cipher in $default13) { $cases += @{ Version='TLSv1.3'; Cipher=$cipher; C12='default'; C13='default'; Expected=$cipher } }
# 两种版本均有自定义正向/不匹配负向；对端锁定版本，不允许回退造成假阳性。
$cases += @{ Version='TLSv1.2'; Cipher=$default12[0]; C12=$default12[0]; C13=$default13[2]; Expected=$default12[0] }
$cases += @{ Version='TLSv1.3'; Cipher=$default13[2]; C12=$default12[0]; C13=$default13[2]; Expected=$default13[2] }
$cases += @{ Version='TLSv1.2'; Cipher=$default12[4]; C12=$default12[0]; C13=$default13[2]; Expected='fail' }
$cases += @{ Version='TLSv1.3'; Cipher=$default13[0]; C12=$default12[0]; C13=$default13[2]; Expected='fail' }
foreach ($oldCipher in 'ECDHE-RSA-AES128-SHA256','TLS_AES_128_CCM_SHA256','TLS_AES_128_CCM_8_SHA256') {
    $version = if ($oldCipher.StartsWith('TLS_')) { 'TLSv1.3' } else { 'TLSv1.2' }
    $cases += @{ Version=$version; Cipher=$oldCipher; C12='default'; C13='default'; Expected='fail' }
}

# 套件相同且不额外限制版本，拒绝结果必须由新配置的协议下限产生。
$cases += @{ Version='TLSv1.3'; Cipher=$default13[2]; C12='default'; C13='default'; Minimum='tls13'; Expected=$default13[2] }
$cases += @{ Version='TLSv1.2'; Cipher=$default12[0]; C12='default'; C13='default'; Minimum='tls13'; Expected='fail' }
$cases += @{ Version='TLSv1.2'; Cipher=$default12[0]; C12='default'; C13='default'; Minimum='restore12'; Expected=$default12[0] }

$passed = 0
foreach ($side in 'client','server') {
    foreach ($case in $cases) {
        $port = New-TestPort
        $kind = if ($case.Cipher.Contains('ECDSA')) { 'ecdsa' } else { 'rsa' }
        $cert = Join-Path $runRoot "$kind-cert.pem"
        $key = Join-Path $runRoot "$kind-key.pem"
        $tlsArguments = if ($case.Version -eq 'TLSv1.2') { @('-tls1_2','-cipher',$case.Cipher) }
                        else { @('-tls1_3','-ciphersuites',$case.Cipher) }
        $minimum = if ($case.Minimum) { $case.Minimum } else { 'default' }
        $probeArguments = @("--$side", "$port", $case.C12, $case.C13, $cert, $key, $cert, $case.Version, $case.Expected, $minimum)
        $peer = $null
        $probe = $null
        $peerOut = $null
        $peerError = $null
        $label = '{0:D2}-{1}-{2}' -f ($passed + 1),$side,$case.Cipher
        if ($minimum -ne 'default') { $label += '-' + $minimum }
        try {
            if ($side -eq 'client') {
                $peer = Start-TestProcess $OpenSslExe (@('s_server','-accept',"127.0.0.1:$port",'-cert',$cert,'-key',$key,'-CAfile',$cert,'-Verify','1','-verify_return_error','-www') + $tlsArguments)
                $peerOut = $peer.StandardOutput.ReadToEndAsync()
                $peerError = $peer.StandardError.ReadToEndAsync()
                # s_server 可处理多连接；此无 TLS 的探测只确认本次进程已监听。
                $ready = $false
                for ($attempt=0; $attempt -lt 100; $attempt++) {
                    if ($peer.HasExited) { throw 'OpenSSL 测试服务提前退出' }
                    $tcp = [Net.Sockets.TcpClient]::new()
                    try { $tcp.Connect('127.0.0.1',$port); $ready=$true; break }
                    catch { Start-Sleep -Milliseconds 20 }
                    finally { $tcp.Dispose() }
                }
                if (-not $ready) { throw 'OpenSSL 测试服务未就绪' }
                $probe = Start-TestProcess $TestExe $probeArguments
                $probeOut = $probe.StandardOutput.ReadToEndAsync()
            } else {
                $probe = Start-TestProcess $TestExe $probeArguments
                $prefix = ''
                do {
                    $lineTask = $probe.StandardOutput.ReadLineAsync()
                    if (-not $lineTask.Wait(10000)) { throw 'Cross-Socket 测试服务未就绪' }
                    $line = $lineTask.Result
                    if ($null -eq $line) { throw "Cross-Socket 提前退出: $prefix" }
                    $prefix += $line + "`n"
                } while ($line -ne 'LISTENING')
                $probeOut = $probe.StandardOutput.ReadToEndAsync()
                $peer = Start-TestProcess $OpenSslExe (@('s_client','-connect',"127.0.0.1:$port",'-servername','localhost','-cert',$cert,'-key',$key,'-CAfile',$cert,'-verify_return_error','-verify_hostname','localhost','-brief') + $tlsArguments)
                $peerOut = $peer.StandardOutput.ReadToEndAsync()
                $peerError = $peer.StandardError.ReadToEndAsync()
            }
            $probeError = $probe.StandardError.ReadToEndAsync()
            if (-not $probe.WaitForExit(15000)) { throw '握手测试进程超时' }
            $result = $probeOut.Result + $probeError.Result
            if ($side -eq 'server') { $result = $prefix + $result }
            $result | Set-Content -LiteralPath (Join-Path $runRoot "$label.log") -Encoding utf8
            if ($probe.ExitCode -ne 0) { throw "$label 失败: $result" }
            $expectedText = if ($case.Expected -eq 'fail') { 'HANDSHAKE REJECTED' }
                            else { 'HANDSHAKE ' + $case.Version + ' ' + $case.Expected }
            if (-not $result.Contains($expectedText)) { throw "$label 缺少真实握手结果" }
            $passed++
            Write-Output "PASS $label"
        } finally {
            if ($peer) {
                if (-not $peer.HasExited) { $peer.Kill(); $peer.WaitForExit() }
                if ($peerOut -and $peerError) {
                    ($peerOut.Result + $peerError.Result) | Set-Content -LiteralPath (Join-Path $runRoot "$label-peer.log") -Encoding utf8
                }
            }
            Stop-TestProcess $probe
            Stop-TestProcess $peer
        }
    }
}
Write-Output "TLS handshake tests: $passed/$($cases.Count * 2) PASS; logs: $runRoot"
