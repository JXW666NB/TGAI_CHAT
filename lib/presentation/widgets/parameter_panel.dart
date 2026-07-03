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

            // === 基础参数 ===
            _sectionHeader(context, '基础参数'),
            _buildSlider(
              context,
              label: '温度',
              hint: '越高输出越随机，越低越确定。创意任务 0.8-1.2，代码/翻译 0.2-0.5',
              value: settings.temperature,
              min: 0.0,
              max: 2.0,
              divisions: 40,
              onChanged: (v) => settings.temperature = double.parse(v.toStringAsFixed(2)),
            ),
            _buildSlider(
              context,
              label: '最大长度',
              hint: '最多生成多少个 token。短回答 64-128，长回答 512+',
              value: settings.maxTokens.toDouble(),
              min: 16,
              max: 2048,
              divisions: 63,
              onChanged: (v) => settings.maxTokens = v.round(),
            ),
            _buildSlider(
              context,
              label: '上下文长度',
              hint: '保留多少历史 token。越大上下文越完整，但推理越慢',
              value: settings.contextLength.toDouble(),
              min: 128,
              max: 4096,
              divisions: 31,
              onChanged: (v) => settings.contextLength = v.round(),
            ),

            const SizedBox(height: 8),
            _sectionHeader(context, '采样策略'),
            _buildSlider(
              context,
              label: 'Top K',
              hint: '每步只从概率最高的 K 个词中采样。越小越保守，越大越多样',
              value: settings.topK.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (v) => settings.topK = v.round(),
            ),
            _buildSlider(
              context,
              label: 'Top P',
              hint: '核采样阈值。累积概率达到 P 就截断。0.9 适合大多数场景',
              value: settings.topP,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (v) => settings.topP = double.parse(v.toStringAsFixed(2)),
            ),
            _buildSlider(
              context,
              label: '重复惩罚',
              hint: '>1.0 惩罚已出现的词，防止车轱辘话。1.1 适中，1.2 强力',
              value: settings.repeatPenalty,
              min: 1.0,
              max: 2.0,
              divisions: 20,
              onChanged: (v) => settings.repeatPenalty = double.parse(v.toStringAsFixed(2)),
            ),

            const SizedBox(height: 8),
            _sectionHeader(context, '性能（影响速度和显存）'),
            _buildSlider(
              context,
              label: '预填充窗口',
              hint: '第一步用多少 token 建上下文。越大首 Token 越慢但越准确',
              value: settings.prefillWindow.toDouble(),
              min: 4,
              max: 128,
              divisions: 31,
              onChanged: (v) => settings.prefillWindow = v.round(),
            ),
            _buildSlider(
              context,
              label: '解码窗口',
              hint: '后续每步用多少 token。4=极快但质量差，64=质量好但极慢，16=平衡',
              value: settings.decodeWindow.toDouble(),
              min: 2,
              max: 64,
              divisions: 31,
              onChanged: (v) => settings.decodeWindow = v.round(),
            ),
            _buildSlider(
              context,
              label: '线程数',
              hint: 'CPU 推理线程数。建议设为手机核心数（4-8），过高反而变慢',
              value: settings.nThreads.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              onChanged: (v) => settings.nThreads = v.round(),
            ),

            const SizedBox(height: 12),
            _sectionHeader(context, '加速后端'),
            _buildToggle(
              context,
              label: 'ARM Compute Library',
              hint: '启用 ARM 官方 CPU 加速库（NEON 汇编优化）。部分手机可能不兼容，关闭则回退 XNNPACK',
              value: settings.useACL,
              onChanged: (v) => settings.useACL = v,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildToggle(
    BuildContext context, {
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(
    BuildContext context, {
    required String label,
    required String hint,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final display = value.roundToDouble() == value ? value.toInt().toString() : value.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
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
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
