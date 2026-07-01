import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/providers/settings_provider.dart';

class ParameterPanel extends StatelessWidget {
  final bool expanded;

  const ParameterPanel({super.key, this.expanded = true});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.initialized) return const SizedBox.shrink();

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
                Icon(Icons.tune, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('生成参数', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const Divider(height: 24),
            _buildSlider(
              context,
              label: '温度',
              value: settings.temperature,
              min: 0.0,
              max: 2.0,
              divisions: 40,
              onChanged: (v) => settings.temperature = double.parse(v.toStringAsFixed(2)),
            ),
            _buildSlider(
              context,
              label: '最大长度',
              value: settings.maxTokens.toDouble(),
              min: 16,
              max: 2048,
              divisions: 63,
              onChanged: (v) => settings.maxTokens = v.round(),
            ),
            _buildSlider(
              context,
              label: '上下文长度',
              value: settings.contextLength.toDouble(),
              min: 128,
              max: 4096,
              divisions: 31,
              onChanged: (v) => settings.contextLength = v.round(),
            ),
            _buildSlider(
              context,
              label: 'Top K',
              value: settings.topK.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (v) => settings.topK = v.round(),
            ),
            _buildSlider(
              context,
              label: 'Top P',
              value: settings.topP,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (v) => settings.topP = double.parse(v.toStringAsFixed(2)),
            ),
            _buildSlider(
              context,
              label: '重复惩罚',
              value: settings.repeatPenalty,
              min: 1.0,
              max: 2.0,
              divisions: 20,
              onChanged: (v) => settings.repeatPenalty = double.parse(v.toStringAsFixed(2)),
            ),
            _buildSlider(
              context,
              label: '线程数',
              value: settings.nThreads.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              onChanged: (v) => settings.nThreads = v.round(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final display = value.roundToDouble() == value ? value.toInt().toString() : value.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(display, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
