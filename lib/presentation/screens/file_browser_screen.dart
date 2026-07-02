import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

/// 内置文件浏览器 — 专为国产手机（小米等）设计，绕过系统文件选择器的 Scoped Storage 限制
class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  /// 用户选择的 .tg 文件完整路径，null 表示取消
  static String? selectedPath;

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  String _currentPath = '/storage/emulated/0';
  List<FileSystemEntity> _items = [];
  bool _loading = true;
  String? _error;
  bool _hasStorageAccess = false;

  // 常用存储路径（国产手机优先）
  static const _commonStoragePaths = [
    '/storage/emulated/0',
    '/sdcard',
    '/mnt/sdcard',
  ];

  static const _commonStartPaths = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/storage/emulated/0/Documents',
    '/sdcard/Download',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (Platform.isAndroid) {
      // 先尝试请求 MANAGE_EXTERNAL_STORAGE（Android 11+ 必需）
      var manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        manageStatus = await Permission.manageExternalStorage.request();
      }
      if (manageStatus.isGranted) {
        _hasStorageAccess = true;
      } else {
        // 回退到普通存储权限
        var storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          storageStatus = await Permission.storage.request();
        }
        _hasStorageAccess = storageStatus.isGranted;
      }

      if (!_hasStorageAccess) {
        setState(() {
          _error = '需要存储权限才能浏览文件\n请在系统设置中授予"所有文件访问权限"';
          _loading = false;
        });
        return;
      }

      // 检测可用的存储路径
      for (final path in _commonStoragePaths) {
        if (await Directory(path).exists()) {
          _currentPath = path;
          break;
        }
      }
    }

    await _loadDir(_currentPath);
  }

  Future<void> _loadDir(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPath = path;
    });

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        // 尝试回退到常用目录
        for (final fb in _commonStartPaths) {
          if (await Directory(fb).exists()) {
            _currentPath = fb;
            break;
          }
        }
      }

      final all = await Directory(_currentPath).list().toList();
      // 排序：目录在前，文件在后；各自按名称排序
      all.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        final aName = a.path.split('/').last.toLowerCase();
        final bName = b.path.split('/').last.toLowerCase();
        return aName.compareTo(bName);
      });

      // 过滤：只显示目录和 .tg 文件
      _items = all.where((e) {
        if (e is Directory) {
          final name = e.path.split('/').last;
          // 隐藏目录
          if (name.startsWith('.')) return false;
          return true;
        }
        return e.path.toLowerCase().endsWith('.tg');
      }).toList();

      _loading = false;
    } catch (e) {
      _error = '无法访问目录: $e';
      _loading = false;
    }
    if (mounted) setState(() {});
  }

  void _goUp() {
    final parent = Directory(_currentPath).parent.path;
    if (parent != _currentPath) {
      _loadDir(parent);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择 .TG 模型文件', style: TextStyle(fontSize: 16)),
            Text(
              _currentPath,
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '快速跳转',
            onPressed: _showQuickJump,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('打开设置'),
                onPressed: () => openAppSettings(),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _loadDir(_currentPath),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('此目录没有 .TG 文件', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 8),
            if (_currentPath != '/')
              TextButton.icon(
                icon: const Icon(Icons.arrow_upward),
                label: const Text('返回上级目录'),
                onPressed: _goUp,
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 返回上级
        if (_currentPath != '/')
          ListTile(
            leading: const Icon(Icons.arrow_upward),
            title: const Text('..'),
            onTap: _goUp,
            dense: true,
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final entity = _items[index];
              final name = entity.path.split('/').last;

              if (entity is Directory) {
                return ListTile(
                  leading: const Icon(Icons.folder, color: Colors.amber),
                  title: Text(name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _loadDir(entity.path),
                );
              }

              // .tg 文件
              final file = entity as File;
              return FutureBuilder<FileStat>(
                future: file.stat(),
                builder: (context, snapshot) {
                  final size = snapshot.hasData ? _formatSize(snapshot.data!.size) : '';
                  return ListTile(
                    leading: Icon(Icons.insert_drive_file, color: Theme.of(context).colorScheme.primary),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(size, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                    trailing: const Icon(Icons.check_circle_outline),
                    onTap: () {
                      FileBrowserScreen.selectedPath = file.path;
                      Navigator.pop(context);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showQuickJump() {
    final locations = <String>[
      ..._commonStartPaths,
      ..._commonStoragePaths,
    ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('快速跳转', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...locations.map((loc) => ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(loc),
                  onTap: () {
                    Navigator.pop(ctx);
                    _loadDir(loc);
                  },
                )),
          ],
        ),
      ),
    );
  }
}
