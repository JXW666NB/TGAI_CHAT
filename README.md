# TG CHAT

本地端侧 AI 对话助手，基于 **Flutter + llama.cpp + PyTorch Mobile**，可在 Android 手机/平板本地运行两种格式的模型：

- **GGUF** — 通过 llama.cpp 加载，兼容 Llama、Qwen、Phi 等通用架构。
- **TGAI (.ptl)** — 通过 PyTorch Mobile Lite Interpreter 加载，原生支持 TGAI 自定义 MoE Transformer。

## 功能

- 双引擎本地推理：llama.cpp（GGUF）+ PyTorch Mobile（TGAI .ptl）
- 本地加载 0.5B ~ 4B 参数模型
- 会话管理：新建、切换、重命名、删除
- 生成参数实时调节：温度、Top K、Top P、最大长度、重复惩罚、上下文长度
- 深色/浅色主题切换
- 自适应布局：手机单栏、平板双栏、桌面三栏

## 双引擎架构

```
┌─────────────────────────────────────────┐
│           TG CHAT (Flutter)             │
├─────────────────────────────────────────┤
│  ChatProvider 自动根据模型类型选择引擎   │
├──────────────┬──────────────────────────┤
│   GGUF 模型   │     TGAI .ptl 模型        │
│  LlamaService │     PytorchService        │
├──────────────┼──────────────────────────┤
│  Dart FFI    │   MethodChannel/EventChannel│
│  tgchat.cpp  │   TgaiInference.kt         │
│  libllama.so │   pytorch_android_lite     │
└──────────────┴──────────────────────────┘
```

切换模型时会自动卸载上一个引擎并加载对应引擎，无需手动重启应用。

## 项目结构

```
tg_chat/
├── lib/                              # Dart 代码
│   ├── core/                         # 主题、配置、自适应布局
│   ├── data/                         # 会话/消息持久化（SQLite）
│   ├── domain/models/                # 数据模型（ModelInfo / ChatSession / ChatMessage）
│   ├── domain/providers/             # 状态管理
│   ├── ffi/                          # llama.cpp FFI 绑定
│   ├── services/                     # 推理服务（LlamaService / PytorchService）
│   ├── presentation/screens/         # 页面
│   └── presentation/widgets/         # 组件
├── android/app/src/main/cpp/         # C++ wrapper（tgchat.cpp / CMakeLists.txt）
├── android/app/src/main/kotlin/.../  # Kotlin 插件（TgaiInference / TgaiTokenizer）
├── setup_env.ps1                     # 一键安装开发环境
├── init_project.ps1                  # 生成项目骨架并构建双引擎 APK
└── pubspec.yaml
```

## 环境要求

- Windows 10/11
- 管理员权限（用于修改环境变量）
- 约 15GB 磁盘空间（Flutter + Android SDK + NDK + llama.cpp）
- 一部 Android 7.0+（API 24，arm64-v8a）手机或平板

## 快速开始

1. 右键 PowerShell，选择「以管理员身份运行」。
2. 进入项目目录：
   ```powershell
   cd d:\TGAI\tg_chat
   ```
3. 安装环境（只需执行一次）：
   ```powershell
   .\setup_env.ps1
   ```
4. 初始化项目并构建双引擎 APK：
   ```powershell
   .\init_project.ps1
   ```
5. 构建完成后，APK 位于：
   ```
   build\app\outputs\flutter-apk\app-release.apk
   ```

## 安装到手机

```powershell
adb install build\app\outputs\flutter-apk\app-release.apk
```

## 导入模型

### 导入 GGUF 模型

1. 将 `.gguf` 模型文件放到手机存储。
2. 打开 TG CHAT → 模型 → 点击 **GGUF** 按钮导入。
3. 选中模型，返回对话页开始聊天。

### 导入 TGAI 模型

TGAI 模型需要三个文件成组导入：

- `{name}_prefill.ptl`
- `{name}_decode.ptl`
- `tokenizer.json`

步骤：

1. 将三个文件放到同一目录。
2. 打开 TG CHAT → 模型 → 点击 **TGAI** 按钮。
3. 选择 `{name}_prefill.ptl`，应用会自动匹配同目录的 `_decode.ptl` 与 `tokenizer.json`。
4. 选中模型后即可对话。

## 导出 TGAI 模型

在 PC 端使用 `scripts/export_pytorch_mobile.py` 将 TGAI PyTorch checkpoint 转换为移动端格式：

```bash
# 进入 TGAI 项目根目录
cd d:\TGAI

python scripts/export_pytorch_mobile.py \
  --checkpoint checkpoints/milestone.pt \
  --out_dir exported/
```

输出文件：

```
exported/
├── tgai_prefill.ptl
├── tgai_decode.ptl
└── tokenizer.json
```

将这三个文件一起复制到手机，按「导入 TGAI 模型」步骤操作即可。

## 将 TGAI 导出为 GGUF（可选）

如果想让同一个 TGAI checkpoint 也能通过 llama.cpp 运行，可再转换为 GGUF：

```bash
python scripts/export_for_mobile.py \
  --checkpoint checkpoints/milestone.pt \
  --out tgai.gguf \
  --quant q4_k_m
```

然后按「导入 GGUF 模型」步骤操作。

## 注意事项

- 当前 APK 仅打包 **arm64-v8a** ABI，因为 llama.cpp 预编译库只提供该架构。
- 首次加载模型需要几秒到几十秒，取决于模型大小和手机性能。
- 4B 模型建议至少 6GB RAM，Q4_K_M 量化约 2.5GB。
- 推理完全在本地进行，不需要网络。
- **重复惩罚建议保持 1.0**：根据训练经验，0.5B 小模型在重复惩罚（如 1.05）下容易出现模型崩溃。

## 常见问题

**Q: 构建时提示 libllama.so 找不到？**  
A: 确保先以管理员身份运行 `setup_env.ps1` 下载 llama.cpp Android 二进制。

**Q: 运行时报 `MissingPluginException`？**  
A: 执行 `flutter pub get` 后重新构建；若仍报错，重新运行 `init_project.ps1` 合并自定义 Kotlin 插件。

**Q: PyTorch Mobile 模型加载失败？**  
A: 确认三个文件（`_prefill.ptl`、`_decode.ptl`、`tokenizer.json`）在同一目录且通过 `_prefill.ptl` 导入；确认手机为 arm64-v8a 架构。

**Q: 模型回复乱码？**  
A: 在设置页检查「对话模板」是否与模型训练格式一致。默认模板为 TGAI 格式。
