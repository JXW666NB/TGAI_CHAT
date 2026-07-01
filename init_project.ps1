#Requires -RunAsAdministrator
<#
.SYNOPSIS
    初始化 TG CHAT Flutter 项目并构建 release APK。
.DESCRIPTION
    1) 检查 Flutter / Java 是否就绪
    2) 备份当前 lib / android / pubspec.yaml 等自定义内容
    3) flutter create --overwrite 生成完整骨架
    4) 还原自定义 Dart 代码、Android 配置、Kotlin 源码与资源
    5) flutter pub get + flutter build apk --release
    6) 输出 APK 路径与安装命令
#>
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ProjectDir = "$PSScriptRoot"
$ToolsDir = "D:\tgchat_tools"
$ApkOutputDir = "$ProjectDir\build\app\outputs\flutter-apk"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

Push-Location $ProjectDir

try {
    # 1. 检查环境
    Write-Step "检查构建环境"
    foreach ($cmd in @("flutter", "java")) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw "$cmd 命令未找到，请先以管理员身份运行 setup_env.ps1"
        }
        Write-Host "  $cmd : $((Get-Command $cmd).Source)"
    }
    Write-Success "环境检查通过"

    # 2. 备份当前自定义代码
    Write-Step "备份自定义代码"
    $backupItems = @(
        @{ Src = "lib"; Dst = "lib_backup" },
        @{ Src = "android"; Dst = "android_backup" },
        @{ Src = "pubspec.yaml"; Dst = "pubspec.yaml.backup" }
    )
    foreach ($item in $backupItems) {
        $src = "$ProjectDir\$($item.Src)"
        $dst = "$ProjectDir\$($item.Dst)"
        if (Test-Path $src) {
            Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -Path $src -Destination $dst -Recurse -Force
            Write-Host "  已备份 $($item.Src)"
        }
    }

    # 3. flutter create 生成骨架
    Write-Step "生成 Flutter 项目骨架"
    flutter config --no-analytics
    flutter create --platforms=android --project-name=tg_chat --org=com.example . --overwrite

    # 4. 还原 pubspec.yaml
    Write-Step "还原 pubspec.yaml"
    Copy-Item -Path "$ProjectDir\pubspec.yaml.backup" -Destination "$ProjectDir\pubspec.yaml" -Force

    # 5. 还原 lib
    Write-Step "还原 Dart 源码"
    Remove-Item "$ProjectDir\lib" -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$ProjectDir\lib_backup" -Destination "$ProjectDir\lib" -Recurse -Force

    # 6. 合并 Android 配置：保留 flutter create 生成的 wrapper/mipmap，覆盖自定义文件
    Write-Step "合并 Android 配置"
    $customFiles = @(
        "android\build.gradle",
        "android\settings.gradle",
        "android\gradle.properties",
        "android\app\build.gradle",
        "android\app\src\main\AndroidManifest.xml",
        "android\app\src\main\res\values\styles.xml",
        "android\app\src\main\res\drawable\launch_background.xml"
    )
    foreach ($rel in $customFiles) {
        $src = "$ProjectDir\android_backup\$rel"
        $dst = "$ProjectDir\$rel"
        if (Test-Path $src) {
            New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
            Copy-Item -Path $src -Destination $dst -Force
            Write-Host "  已还原 $rel"
        }
    }

    # 7. 还原 Kotlin 源码（覆盖 flutter create 生成的 MainActivity.kt）
    Write-Step "还原 Kotlin 源码"
    $kotlinBackup = "$ProjectDir\android_backup\app\src\main\kotlin\com\example\tg_chat"
    $kotlinDst = "$ProjectDir\android\app\src\main\kotlin\com\example\tg_chat"
    if (Test-Path $kotlinBackup) {
        Remove-Item $kotlinDst -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $kotlinDst | Out-Null
        Copy-Item -Path "$kotlinBackup\*" -Destination $kotlinDst -Recurse -Force
        Write-Host "  已还原 MainActivity / TgaiInference / TgaiTokenizer"
    }

    # 8. 获取依赖并构建
    Write-Step "获取 Flutter 依赖"
    flutter pub get

    Write-Step "构建 release APK（PyTorch Mobile / TGAI）"
    flutter build apk --release

    # 9. 校验输出
    $apkPath = "$ApkOutputDir\app-release.apk"
    if (-not (Test-Path $apkPath)) {
        throw "APK 构建失败，未找到 $apkPath"
    }

    Write-Success ""
    Write-Success "=============================="
    Write-Success "  TGAI APK 构建成功！"
    Write-Success "=============================="
    Write-Host ""
    Write-Host "APK 路径: $apkPath"
    Write-Host "文件大小: $([math]::Round((Get-Item $apkPath).Length / 1MB, 2)) MB"
    Write-Host ""
    Write-Host "安装到手机:"
    Write-Host "  adb install `"$apkPath`""
    Write-Host ""
    Write-Host "支持的模型格式:"
    Write-Host "  - TGAI .ptl (PyTorch Mobile: *_prefill.ptl + *_decode.ptl + tokenizer.json)"
    Write-Host "=============================="
}
finally {
    Pop-Location
}
