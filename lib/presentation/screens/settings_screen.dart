import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../domain/providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final themeNotifier = context.watch<ThemeNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('外观', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {themeNotifier.mode},
                    onSelectionChanged: (set) => themeNotifier.setMode(set.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('对话模板', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    label: '提示词模板',
                    value: settings.promptTemplate,
                    onChanged: (v) => settings.promptTemplate = v,
                    maxLines: 4,
                    helper: '可用占位符: {history}, {input}, {userPrefix}, {assistantPrefix}, {system}',
                  ),
                  _buildTextField(
                    context,
                    label: '用户前缀',
                    value: settings.userPrefix,
                    onChanged: (v) => settings.userPrefix = v,
                  ),
                  _buildTextField(
                    context,
                    label: '助手前缀',
                    value: settings.assistantPrefix,
                    onChanged: (v) => settings.assistantPrefix = v,
                  ),
                  _buildTextField(
                    context,
                    label: '系统提示词',
                    value: settings.systemPrompt,
                    onChanged: (v) => settings.systemPrompt = v,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('调试', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    title: const Text('显示调试面板'),
                    subtitle: const Text('在对话页显示当前参数与状态'),
                    value: settings.debugMode,
                    onChanged: (v) => settings.debugMode = v,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () async {
              await settings.resetToDefaults();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢复默认参数')));
              }
            },
            child: const Text('恢复默认参数'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: TextEditingController(text: value),
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, helperText: helper),
        onChanged: onChanged,
      ),
    );
  }
}
