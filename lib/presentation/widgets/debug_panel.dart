import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/settings_provider.dart';

class DebugPanel extends StatelessWidget {
  final SettingsProvider settings;
  final ChatProvider chat;

  const DebugPanel({super.key, required this.settings, required this.chat});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('调试信息', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => Clipboard.setData(ClipboardData(text: _buildDebugText())),
                  tooltip: '复制',
                ),
              ],
            ),
            const Divider(height: 24),
            Text(_buildDebugText(), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }

  String _buildDebugText() {
    final sb = StringBuffer();
    sb.writeln('modelLoaded: ${chat.modelLoaded}');
    sb.writeln('nCtx: ${chat.modelLoaded ? 'unknown' : 'N/A'}');
    sb.writeln('isGenerating: ${chat.isGenerating}');
    sb.writeln('isLoadingModel: ${chat.isLoadingModel}');
    sb.writeln('messages: ${chat.messages.length}');
    sb.writeln('sessions: ${chat.sessions.length}');
    if (chat.error != null) sb.writeln('error: ${chat.error}');
    sb.writeln('--- settings ---');
    sb.writeln(settings.toDebugJson());
    return sb.toString();
  }
}
