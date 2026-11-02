# 从脚本所在仓库开始，保留所有重解析点以及它们引用的目录树。
$ErrorActionPreference = 'Stop'
$root = (Get-Item -LiteralPath $PSScriptRoot).FullName
$prefix = $root.TrimEnd('\') + '\'
$extensions = '.dcu', '.drc', '.map', '.o', '.log'

function Clear-BuildFiles([string]$Directory, [bool]$EntireDirectory) {
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if (-not $item.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "目录超出清理范围 $($item.FullName)"
        }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Name -eq '.git') {
            continue
        }
        if ($item.PSIsContainer) {
            $remove = $EntireDirectory -or $item.Name -in '__history', '__recovery' -or $item.Name -like '*.log'
            Clear-BuildFiles $item.FullName $remove
            if ($remove -and -not (Get-ChildItem -LiteralPath $item.FullName -Force | Select-Object -First 1)) {
                [IO.Directory]::Delete($item.FullName, $false)
            }
        } elseif ($EntireDirectory -or $item.Extension -in $extensions) {
            Remove-Item -LiteralPath $item.FullName -Force
        }
    }
}

Clear-BuildFiles $root $false
