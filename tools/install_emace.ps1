param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [string]$GodotPath = ''
)
$ErrorActionPreference = 'Stop'
$gameRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $GodotPath) {
    $GodotPath = Join-Path (Split-Path $gameRoot -Parent) 'Tools\Godot\Godot.exe'
}
$engineFile = (Resolve-Path -LiteralPath $GodotPath).Path
$packageFile = (Resolve-Path -LiteralPath $ZipPath).Path
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$importWork = Join-Path $tempBase ('Dinkum-Emace-' + [Guid]::NewGuid().ToString('N'))
$destination = Join-Path $gameRoot 'local_assets\emace'
try {
    New-Item -ItemType Directory -Path $importWork | Out-Null
    Expand-Archive -LiteralPath $packageFile -DestinationPath $importWork
    $packRoot = Join-Path $importWork 'SlavicWorldFree'
    if (-not (Test-Path -LiteralPath (Join-Path $packRoot 'LICENSE.txt'))) {
        throw 'ZIP不含SlavicWorldFree/LICENSE.txt，请从原作者页面下载指定资源包。'
    }
    Write-Host '导入原包供Godot解析，随后仅保留一栋房屋和一个木箱。首次导入可能需要几分钟。'
    # Start-Process显式等待，兼容GUI版Godot.exe；目录有空格时必须保留参数引号。
    $importArgs = @('--headless', '--editor', '--path', ('"' + $packRoot + '"'), '--quit')
    $importProcess = Start-Process -FilePath $engineFile -ArgumentList $importArgs -WindowStyle Hidden -Wait -PassThru
    if ($importProcess.ExitCode -ne 0) { throw '资源包导入失败。' }
    $convertArgs = @('--headless', '--path', ('"' + $packRoot + '"'), '--script', ('"' + (Join-Path $PSScriptRoot 'emace_import.gd') + '"'), '--', '--output', ('"' + $destination + '"'))
    $convertProcess = Start-Process -FilePath $engineFile -ArgumentList $convertArgs -WindowStyle Hidden -Wait -PassThru
    if ($convertProcess.ExitCode -ne 0) { throw '试换素材转换失败。' }
    foreach ($required in @('hut.scn', 'crate.scn', 'LICENSE.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $destination $required))) { throw "缺少输出：$required" }
    }
    Write-Host "已安装到 $destination。该目录已被Git忽略；原作者许可禁止独立素材再分发。"
} finally {
    # 只删除这次创建的随机临时目录，并先验证绝对路径仍在系统临时目录中。
    $cleanupTarget = [IO.Path]::GetFullPath($importWork)
    if ($cleanupTarget.StartsWith($tempBase.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $cleanupTarget -Leaf) -match '^Dinkum-Emace-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $cleanupTarget)) {
        Remove-Item -LiteralPath $cleanupTarget -Recurse -Force
    }
}
