import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/adaptive.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/providers/settings_provider.dart';
import '../widgets/debug_panel.dart';
import '../widgets/parameter_panel.dart';
import '../widgets/session_tile.dart';
import 'chat_screen.dart';
import 'models_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final _destinations = const [
    (icon: Icons.chat_outlined, active: Icons.chat, label: '对话'),
    (icon: Icons.folder_outlined, active: Icons.folder, label: '模型'),
    (icon: Icons.settings_outlined, active: Icons.settings, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final type = Adaptive.of(context);
    final isPhone = type == ScreenType.phone;
    final isDesktop = type == ScreenType.desktop;
    final chat = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();

    final content = _buildContent(isPhone: isPhone);

    if (isPhone) {
      return Scaffold(
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: _destinations
              .map((d) => NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.active),
                    label: d.label,
                  ))
              .toList(),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: _destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.active),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          if (_selectedIndex == 0) ...[
            SizedBox(width: 280, child: _buildSessionsPanel(context, chat)),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: content),
          if (isDesktop && _selectedIndex == 0) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const ParameterPanel(),
                    if (settings.debugMode) DebugPanel(settings: settings, chat: chat),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent({required bool isPhone}) {
    switch (_selectedIndex) {
      case 0:
        return ChatScreen(
          showAppBar: isPhone,
          sidePanel: isPhone || Adaptive.of(context) != ScreenType.desktop
              ? null
              : null, // 桌面端参数面板已在 home 里处理
        );
      case 1:
        return const ModelsScreen();
      case 2:
        return const SettingsScreen();
      default:
        return ChatScreen(showAppBar: isPhone);
    }
  }

  Widget _buildSessionsPanel(BuildContext context, ChatProvider chat) {
    return Scaffold(
      appBar: AppBar(
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
      body: chat.sessions.isEmpty
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
                  onTap: () => chat.selectSession(s.id),
                  onDelete: () => chat.deleteSession(s.id),
                  onRename: (title) => chat.renameSession(s.id, title),
                );
              },
            ),
    );
  }
}
