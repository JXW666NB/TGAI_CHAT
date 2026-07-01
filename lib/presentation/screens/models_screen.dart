import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../domain/models/model_info.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/models_provider.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelsProvider>();
    final chat = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('模型管理')),
      body: Column(
        children: [
          if (models.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(models.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: models.models.isEmpty
                ? _buildEmpty(context)
                : ListView.builder(
                    itemCount: models.models.length,
                    itemBuilder: (context, index) {
                      final m = models.models[index];
                      final selected = models.current?.id == m.id;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(Icons.memory_outlined, color: Theme.of(context).colorScheme.primary),
                          ),
                          title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(
                                'PyTorch Mobile (TGAI)',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (selected)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => models.removeModel(m.id),
                              ),
                            ],
                          ),
                          onTap: () {
                            models.selectModel(m.id);
                            chat.unloadModel();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('模型已切换，首次发送消息时加载')),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: models.busy ? null : () => _pickTg(context, models),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('导入 .TG'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('还没有模型', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 8),
          Text('请导入 .TG 模型文件（一个文件包含全部）',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Future<void> _pickTg(BuildContext context, ModelsProvider models) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    if (!path.toLowerCase().endsWith('.tg')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择 .TG 格式的模型文件')));
      return;
    }

    if (!context.mounted) return;
    _showImportDialog(context, models, path);
  }

  void _showImportDialog(BuildContext context, ModelsProvider models, String path) {
    // 先弹出对话框，再异步启动导入
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // ListenableBuilder 监听 ModelsProvider 变化，自动重建 UI
        return ListenableBuilder(
          listenable: models,
          builder: (ctx, _) {
            return AlertDialog(
              title: const Text('导入模型'),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: models.importProgress > 0 ? models.importProgress : null),
                    const SizedBox(height: 16),
                    Text(models.importStatus, style: const TextStyle(fontFamily: 'monospace')),
                    if (models.importCurrentFile.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('文件: ${models.importCurrentFile}',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                    ],
                    if (models.error != null) ...[
                      const SizedBox(height: 12),
                      Text(models.error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              actions: [
                if (models.importing)
                  TextButton(
                    onPressed: () {
                      models.cancelImport();
                    },
                    child: const Text('取消'),
                  ),
                if (!models.importing)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (models.error == null && models.importProgress >= 1.0) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('导入完成')));
                      }
                    },
                    child: const Text('关闭'),
                  ),
              ],
            );
          },
        );
      },
    );

    // 启动导入（异步，弹窗已显示）
    // 完成后通过 ListenableBuilder 自动更新 UI，用户点击"关闭"按钮手动关闭
    models.addTgFile(path);
  }

  Future<void> _pickTgai(BuildContext context, ModelsProvider models) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final lower = path.toLowerCase();
    if (!lower.endsWith('.ptl')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择 .ptl 格式的模型文件')));
      return;
    }
    if (!lower.contains('_prefill')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择 *_prefill.ptl，系统会自动匹配同目录的 _decode.ptl 和 tokenizer.json')),
      );
      return;
    }

    final info = await models.addTgaiModel(path);
    _showResult(context, models, info);
  }

  void _showResult(BuildContext context, ModelsProvider models, ModelInfo? info) {
    if (info == null && models.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: ${models.error}')));
    } else if (info != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入: ${info.name}')));
    }
  }
}
