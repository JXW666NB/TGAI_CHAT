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

            // === 设备信息 ===
            if (settings.deviceInfoLoaded) ...[
              _buildDeviceInfo(context, settings),
              const Divider(height: 24),
            ],

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
              hint: 'CPU 推理线程数。建议设为手机核心数（4-8），过高反而变慢。设为0自动检测',
              value: settings.nThreads.toDouble(),
              min: 0,
              max: 8,
              divisions: 8,
              onChanged: (v) => settings.nThreads = v.round(),
            ),

            const SizedBox(height: 12),
            _sectionHeader(context, '加速后端（改后需重新加载模型）'),
            _buildProviderDropdown(context, settings),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo(BuildContext context, SettingsProvider settings) {
    final info = settings.deviceInfo;
    final recommended = info['recommended'] as String? ?? 'CPU_ACL';
    final soc = info['soc_model'] as String? ?? '';
    final mfr = info['soc_manufacturer'] as String? ?? '';
    final cores = info['cores']?.toString() ?? '?';
    final chipLabel = soc.isNotEmpty && soc != 'unknown'
        ? '$soc ($mfr)'
        : '${info['hardware'] ?? 'unknown'}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已检测到芯片',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chipLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '$cores 核心 · 推荐 $recommended',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderDropdown(BuildContext context, SettingsProvider settings) {
    final recommended = settings.deviceInfo['recommended'] as String? ?? 'CPU_ACL';
    const items = [
      ('auto', '自动（推荐）'),
      ('nnapi', 'NNAPI（NPU/DSP 加速，速度最快）'),
      ('cpu_acl', 'ACL + XNNPACK（CPU 稳定方案）'),
      ('cpu_only', '纯 CPU / XNNPACK（最大兼容性）'),
    ];

    final labels = {
      'auto': '自动选择最优后端（NNAPI > ACL > CPU）。\n当前推荐: $recommended',
      'nnapi': '强制走 Android NNAPI，可能调用 NPU/DSP/GPU。\n速度最快，但部分模型可能不兼容。需要 Android 8.1+',
      'cpu_acl': 'ARM Compute Library (NEON 汇编) + XNNPACK。\n稳定可靠，大多数手机的最佳选择',
      'cpu_only': '纯 XNNPACK CPU 推理。\n部分手机 ACL 有兼容 bug 时的备用方案',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (value, label) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RadioListTile<String>(
              title: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text(
                labels[value] ?? '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
              value: value,
              groupValue: settings.providerMode,
              onChanged: (v) {
                if (v != null) settings.providerMode = v;
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        // 当前实际使用的后端
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 14, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '当前后端: ${settings.providerMode.toUpperCase()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
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
