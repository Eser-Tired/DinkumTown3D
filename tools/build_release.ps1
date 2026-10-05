param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [string]$SigningConfigPath
)
$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path $PSScriptRoot -Parent
$releaseBuild = Join-Path $releaseRoot 'build'
New-Item -ItemType Directory -Force $releaseBuild | Out-Null

# 运行包不含文档和测试；密钥仅从仓库外文件或官方环境变量注入。
if ($SigningConfigPath) {
    $releaseSecretPath = (Resolve-Path -LiteralPath $SigningConfigPath).Path
    if ($releaseSecretPath.StartsWith($releaseRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw '签名配置必须保存在仓库外。'
    }
    $releaseSigning = Get-Content -LiteralPath $releaseSecretPath -Raw | ConvertFrom-Json
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $releaseSigning.keystore
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $releaseSigning.alias
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $releaseSigning.password
}
foreach ($releaseSetting in @('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')) {
    if (-not [Environment]::GetEnvironmentVariable($releaseSetting)) { throw "缺少签名设置：$releaseSetting" }
}
try {
    & $GodotPath --headless --editor --path $releaseRoot --quit
    if ($LASTEXITCODE -ne 0) { throw '资源导入失败。' }
    foreach ($releasePreset in @('Windows Desktop', 'Android')) {
        & $GodotPath --headless --path $releaseRoot --export-release $releasePreset
        if ($LASTEXITCODE -ne 0) { throw "导出失败：$releasePreset" }
    }
    $releaseFiles = @('DinkumTown3D-Windows-x64.exe', 'DinkumTown3D-Android.apk')
    $releaseHashes = foreach ($releaseFile in $releaseFiles) {
        $releasePath = Join-Path $releaseBuild $releaseFile
        if (-not (Test-Path -LiteralPath $releasePath)) { throw "缺少产物：$releaseFile" }
        '{0}  {1}' -f (Get-FileHash -LiteralPath $releasePath -Algorithm SHA256).Hash.ToLowerInvariant(), $releaseFile
    }
    $releaseHashes | Set-Content (Join-Path $releaseBuild 'SHA256SUMS.txt') -Encoding ascii
    Write-Output "构建完成：$releaseBuild；发布前须验证 APK 签名、运行包和验收测试。"
} finally {
    # 凭据不写入导出预设、日志或 Git，也不留在当前构建进程的环境中。
    if ($SigningConfigPath) {
        foreach ($releaseSetting in @('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')) {
            [Environment]::SetEnvironmentVariable($releaseSetting, $null, 'Process')
        }
    }
}
