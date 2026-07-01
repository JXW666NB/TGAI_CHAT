#Requires -RunAsAdministrator
<#
.SYNOPSIS
    一键配置 TG CHAT 开发/构建环境。
.DESCRIPTION
    自动安装 JDK、Flutter、Android SDK、NDK。
    脚本需要管理员权限来修改系统环境变量。
#>
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$User = $env:USERPROFILE
# 安装到 D 盘，避免 C 盘空间不足
$ToolsDir = "D:\tgchat_tools"
$JdkDir = "$ToolsDir\jdk-17"
$FlutterDir = "$ToolsDir\flutter"
$AndroidSdkDir = "$ToolsDir\android-sdk"
$AndroidCmdlineDir = "$AndroidSdkDir\cmdline-tools\latest"
$Ndks = @("26.1.10909125")

function Test-Command {
    param([string]$Cmd)
    $null -ne (Get-Command $Cmd -ErrorAction SilentlyContinue)
}

function Add-ToUserPath {
    param([string[]]$Paths)
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $list = $current -split ";" | Where-Object { $_ }
    foreach ($p in $Paths) {
        if ($p -and ($list -notcontains $p)) {
            $list += $p
        }
    }
    [Environment]::SetEnvironmentVariable("Path", ($list -join ";"), "User")
    $env:Path = ($env:Path -split ";" | Where-Object { $_ }) + $Paths -join ";"
}

function Add-ToUserEnv {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "env:$Name" -Value $Value
}

function Download-File {
    param([string]$Uri, [string]$OutFile)
    Write-Host "下载: $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -MaximumRedirection 10
    if (-not (Test-Path $OutFile)) { throw "下载失败: $Uri" }
}

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
New-Item -ItemType Directory -Force -Path $AndroidSdkDir | Out-Null

# 1. JDK 17
if (-not (Test-Path "$JdkDir\bin\java.exe")) {
    Write-Host "=== 安装 JDK 17 ==="
    $jdkZip = "$ToolsDir\jdk17.zip"
    Download-File -Uri "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.zip" -OutFile $jdkZip
    Expand-Archive -Path $jdkZip -DestinationPath "$ToolsDir\jdk_tmp" -Force
    $expanded = Get-ChildItem "$ToolsDir\jdk_tmp" -Directory | Select-Object -First 1
    Move-Item -Path $expanded.FullName -Destination $JdkDir -Force
    Remove-Item "$ToolsDir\jdk_tmp" -Recurse -Force -ErrorAction SilentlyContinue
}
Add-ToUserEnv -Name "JAVA_HOME" -Value $JdkDir
Add-ToUserPath -Paths @("$JdkDir\bin")
Write-Host "JDK: $JdkDir"

# 2. Flutter
if (-not (Test-Path "$FlutterDir\bin\flutter.bat")) {
    Write-Host "=== 安装 Flutter SDK ==="
    $flutterZip = "$ToolsDir\flutter.zip"
    Download-File -Uri "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.22.2-stable.zip" -OutFile $flutterZip
    Expand-Archive -Path $flutterZip -DestinationPath $ToolsDir -Force
}
Add-ToUserPath -Paths @("$FlutterDir\bin")
Add-ToUserEnv -Name "FLUTTER_ROOT" -Value $FlutterDir
Write-Host "Flutter: $FlutterDir"

# 3. Android SDK cmdline-tools
if (-not (Test-Path "$AndroidCmdlineDir\bin\sdkmanager.bat")) {
    Write-Host "=== 安装 Android SDK cmdline-tools ==="
    $cmdlineZip = "$ToolsDir\cmdline-tools.zip"
    Download-File -Uri "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile $cmdlineZip
    New-Item -ItemType Directory -Force -Path "$AndroidSdkDir\cmdline-tools" | Out-Null
    Expand-Archive -Path $cmdlineZip -DestinationPath "$AndroidSdkDir\cmdline-tools" -Force
    Rename-Item -Path "$AndroidSdkDir\cmdline-tools\cmdline-tools" -NewName "latest" -Force -ErrorAction SilentlyContinue
}
Add-ToUserPath -Paths @("$AndroidCmdlineDir\bin")
Add-ToUserEnv -Name "ANDROID_HOME" -Value $AndroidSdkDir
Add-ToUserEnv -Name "ANDROID_SDK_ROOT" -Value $AndroidSdkDir
Write-Host "Android SDK: $AndroidSdkDir"

# 4. 安装 platforms, build-tools, ndk
Write-Host "=== 安装 Android SDK 组件 ==="
$sdkmanager = "$AndroidCmdlineDir\bin\sdkmanager.bat"
$components = @(
    "platform-tools",
    "platforms;android-34",
    "build-tools;34.0.0",
    "ndk;$($Ndks[0])"
)
for ($i = 0; $i -lt 20; $i++) { "y" } | & $sdkmanager --licenses 2>&1 | Out-Null
foreach ($c in $components) {
    & $sdkmanager --install $c 2>&1 | Out-Null
}
Add-ToUserPath -Paths @("$AndroidSdkDir\platform-tools")

Write-Host ""
Write-Host "=============================="
Write-Host "环境配置完成！"
Write-Host "下一步：以管理员身份运行 init_project.ps1 来生成 Flutter 项目骨架并构建 APK"
Write-Host "=============================="
