import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/chat_session.dart';

class SessionTile extends StatelessWidget {
  final ChatSession session;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onRename;

  const SessionTile({
    super.key,
    required this.session,
    this.selected = false,
    this.onTap,
    this.onDelete,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: selected ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        DateFormat('MM-dd HH:mm').format(session.updatedAt),
        style: theme.textTheme.bodySmall,
      ),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (value) {
          if (value == 'rename') {
            _showRenameDialog(context);
          } else if (value == 'delete') {
            onDelete?.call();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '会话名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) onRename?.call(text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
