import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/models_provider.dart';
import 'file_browser_screen.dart';

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
                    onPressed: models.busy ? null : () => _openFileBrowser(context, models),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('导入 .TG 模型'),
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
          Text('点击下方按钮，使用内置文件浏览器\n选择 .TG 模型文件',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  /// 打开内置文件浏览器让用户选择 .tg 文件
  Future<void> _openFileBrowser(BuildContext context, ModelsProvider models) async {
    // 清除上次选择
    FileBrowserScreen.selectedPath = null;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FileBrowserScreen()),
    );

    final path = FileBrowserScreen.selectedPath;
    if (path == null || !context.mounted) return;

    _showImportDialog(context, models, path);
  }

  /// 显示导入进度对话框
  void _showImportDialog(BuildContext context, ModelsProvider models, String path) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
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
                    LinearProgressIndicator(
                      value: models.importProgress > 0 ? models.importProgress : null,
                    ),
                    const SizedBox(height: 16),
                    Text(models.importStatus, style: const TextStyle(fontFamily: 'monospace')),
                    if (models.importCurrentFile.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '文件: ${models.importCurrentFile}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                    if (models.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        models.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                      ),
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
                    },
                    child: const Text('关闭'),
                  ),
              ],
            );
          },
        );
      },
    );

    // 异步启动导入，弹窗通过 ListenableBuilder 自动更新
    models.addTgFile(path);
  }
}
