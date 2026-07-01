# TG CHAT

本地端侧 AI 对话助手，基于 Flutter + PyTorch Mobile，可在 Android 手机/平板本地运行 TGAI 模型（`.ptl` 格式）。

## 功能

- 本地加载 TGAI 0.5B~4B 参数模型
- 会话管理：新建、切换、重命名、删除
- 参数调节：temperature、topK、topP、maxTokens、repeatPenalty
- 多设备界面：手机单栏 / 平板双栏 / 桌面三栏自适应

## 模型格式

TG CHAT 只支持 **TGAI 模型**，需要同一目录下的三个文件：

```
model_prefill.ptl   # 预填充模块
model_decode.ptl    # 解码生成模块
tokenizer.json      # 分词器词表
```

导入时只需要选择 `*_prefill.ptl`，应用会自动匹配同目录的 `_decode.ptl` 和 `tokenizer.json`。

## 导出 TGAI 模型

在训练环境运行：

```bash
python scripts/export_pytorch_mobile.py \
  --checkpoint checkpoints/milestone.pt \
  --tokenizer tokenizer.json \
  --output-dir exported/
```

输出：

```
exported/
  model_prefill.ptl
  model_decode.ptl
  tokenizer.json
```

把这三个文件传到手机，在 TG CHAT 的「模型」页导入即可。

## 本地开发

### 环境要求

- Windows 10/11
- JDK 17
- Flutter 3.22.2
- Android SDK + NDK 26.1.10909125

### 配置环境

右键 PowerShell → 以管理员身份运行：

```powershell
cd d:\TGAI\tg_chat
.\setup_env.ps1
```

所有依赖默认安装到 `D:\tgchat_tools`，不会占用 C 盘。

### 运行调试

```powershell
cd d:\TGAI\tg_chat
flutter pub get
flutter run
```

### 构建 Release APK

```powershell
cd d:\TGAI\tg_chat
flutter build apk --release
```

APK 输出：`build/app/outputs/flutter-apk/app-release.apk`

## GitHub Actions 自动构建

仓库已配置 `.github/workflows/build_apk.yml`，每次 `git push` 会自动构建 APK。

构建完成后，在 Actions 页面下载 Artifact `tg-chat-apk`。

## 注意事项

- 只支持 **arm64-v8a** 架构的 Android 设备（Android 7.0+，API 24）
- 模型推理完全在本地进行，首次加载模型需要几秒到几十秒
- 建议把 `repeatPenalty` 设置为 **1.0**，小模型在高重复惩罚下容易崩溃
