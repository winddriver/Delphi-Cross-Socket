$ErrorActionPreference = 'Stop'
$repo = (Get-Item -LiteralPath "$PSScriptRoot\..\..\..\..").FullName
$bin = [IO.Directory]::CreateDirectory("$PSScriptRoot\bin").FullName
$fixture = Join-Path $bin ("clear-" + [Guid]::NewGuid().ToString('N'))
$copy = Join-Path $fixture 'project with spaces'
$outside = Join-Path $fixture 'other project'
$link = Join-Path $copy 'linked folder'
try {
    [void][IO.Directory]::CreateDirectory("$copy\__history")
    [void][IO.Directory]::CreateDirectory($outside)
    Copy-Item -LiteralPath "$repo\clear.bat", "$repo\clear.ps1" -Destination $copy
    [IO.File]::WriteAllText("$copy\a b.map", 'remove')
    [IO.File]::WriteAllText("$copy\__history\old.pas", 'remove')
    [IO.File]::WriteAllText("$copy\keep.pas", 'keep')
    [IO.File]::WriteAllText("$outside\keep.map", 'keep')
    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    Push-Location -LiteralPath $outside
    try {
        & "$copy\clear.bat"
        if ($LASTEXITCODE) { throw "clear exited $LASTEXITCODE" }
    } finally { Pop-Location }
    foreach ($name in "$copy\__history", "$copy\a b.map") {
        if (Test-Path -LiteralPath $name) { throw "未清理 $name" }
    }
    foreach ($name in "$copy\keep.pas", "$outside\keep.map", $link) {
        if (-not (Test-Path -LiteralPath $name)) { throw "误删 $name" }
    }
    Write-Output 'PASS clear.bat'
} finally {
    if ([IO.Directory]::Exists($link)) { [IO.Directory]::Delete($link, $false) }
    if ((Test-Path -LiteralPath $fixture) -and
        ((Get-Item -LiteralPath $fixture).Parent.FullName -eq $bin)) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
