import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/models_provider.dart';
import '../../domain/providers/settings_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/debug_panel.dart';
import '../widgets/message_input.dart';
import '../widgets/parameter_panel.dart';
import '../widgets/session_tile.dart';

class ChatScreen extends StatefulWidget {
  final bool showAppBar;
  final Widget? sidePanel;

  const ChatScreen({super.key, this.showAppBar = true, this.sidePanel});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();
    final models = context.watch<ModelsProvider>();

    Widget body = Column(
      children: [
        if (chat.error != null)
          MaterialBanner(
            content: Text(chat.error!, maxLines: 3, overflow: TextOverflow.ellipsis),
            actions: [
              TextButton(
                onPressed: () => chat.sendMessage('你好', settings, models),
                child: const Text('重试'),
              ),
              TextButton(
                onPressed: () => chat.clearCurrentSession(),
                child: const Text('清空'),
              ),
            ],
          ),
        Expanded(
          child: chat.messages.isEmpty
              ? _buildEmpty(context)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chat.messages.length,
                  itemBuilder: (context, index) => ChatBubble(message: chat.messages[index]),
                ),
        ),
        MessageInput(
          isGenerating: chat.isGenerating,
          onStop: () => chat.stopGeneration(),
          onSend: (text) => chat.sendMessage(text, settings, models),
        ),
      ],
    );

    if (widget.sidePanel != null) {
      body = Row(
        children: [
          Expanded(child: body),
          SizedBox(width: 360, child: widget.sidePanel!),
        ],
      );
    }

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(chat.currentSession?.title ?? 'TG CHAT'),
              actions: [
                if (chat.isLoadingModel)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: '参数',
                ),
                IconButton(
                  icon: const Icon(Icons.cleaning_services_outlined),
                  onPressed: () => _confirmClear(context, chat),
                  tooltip: '清空当前会话',
                ),
              ],
            )
          : null,
      drawer: widget.showAppBar ? Drawer(child: _buildSessionsDrawer(context, chat)) : null,
      endDrawer: widget.showAppBar
          ? Drawer(
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const ParameterPanel(),
                      if (settings.debugMode) DebugPanel(settings: settings, chat: chat),
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: body,
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('开始对话', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 8),
          Text('在下方输入消息，TGAI 将在本地运行回复', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildSessionsDrawer(BuildContext context, ChatProvider chat) {
    return Column(
      children: [
        AppBar(
          title: const Text('会话'),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: () => chat.createSession(),
              tooltip: '新建会话',
            ),
          ],
        ),
        Expanded(
          child: chat.sessions.isEmpty
              ? Center(
                  child: Text(
                    '没有会话',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  itemCount: chat.sessions.length,
                  itemBuilder: (context, index) {
                    final s = chat.sessions[index];
                    return SessionTile(
                      session: s,
                      selected: chat.currentSession?.id == s.id,
                      onTap: () {
                        chat.selectSession(s.id);
                        Navigator.pop(context);
                      },
                      onDelete: () => chat.deleteSession(s.id),
                      onRename: (title) => chat.renameSession(s.id, title),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _confirmClear(BuildContext context, ChatProvider chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空会话'),
        content: const Text('确定清空当前会话的所有消息吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              chat.clearCurrentSession();
              Navigator.pop(context);
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
