import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/model_info.dart';

class ModelsProvider extends ChangeNotifier {
  static const _importChannel = MethodChannel('tg_chat/import');
  static const _progressChannel = EventChannel('tg_chat/import_progress');

  final List<ModelInfo> _models = [];
  ModelInfo? _current;
  bool _busy = false;
  String? _error;

  // 导入进度
  double _importProgress = 0;
  String _importStatus = '';
  String _importCurrentFile = '';
  bool _importing = false;

  List<ModelInfo> get models => List.unmodifiable(_models);
  ModelInfo? get current => _current;
  bool get busy => _busy;
  String? get error => _error;
  double get importProgress => _importProgress;
  String get importStatus => _importStatus;
  String get importCurrentFile => _importCurrentFile;
  bool get importing => _importing;

  Future<void> load() async {
    _busy = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('models_list');
      final currentId = prefs.getString('current_model_id');
      _models.clear();
      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        for (final item in list) {
          final m = ModelInfo.fromJson(item as Map<String, dynamic>);
          if (await _validateModelFiles(m)) _models.add(m);
        }
      }
      if (currentId != null) {
        _current = _models.where((m) => m.id == currentId).firstOrNull;
      }
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _validateModelFiles(ModelInfo m) async {
    if (!await File(m.path).exists()) return false;
    if (!await File(m.decodePath).exists()) return false;
    if (!await File(m.tokenizerPath).exists()) return false;
    return true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('models_list', jsonEncode(_models.map((m) => m.toJson()).toList()));
    await prefs.setString('current_model_id', _current?.id ?? '');
  }

  Future<ModelInfo?> addTgFile(String tgPath) async {
    _importing = true;
    _importProgress = 0;
    _importStatus = '准备解压...';
    _importCurrentFile = '';
    _error = null;
    _busy = true;
    notifyListeners();

    StreamSubscription? progressSub;
    final completer = Completer<ModelInfo?>();

    try {
      final file = File(tgPath);
      if (!await file.exists()) throw Exception('文件不存在: $tgPath');

      final totalSize = await file.length();
      _importStatus = '文件大小: ${_formatSize(totalSize)}';
      notifyListeners();

      // 创建输出目录
      final docs = await getApplicationDocumentsDirectory();
      final modelName = p.basenameWithoutExtension(tgPath);
      final modelsDir = Directory(p.join(docs.path, 'tg_chat', 'models', modelName));
      if (await modelsDir.exists()) await modelsDir.delete(recursive: true);
      await modelsDir.create(recursive: true);

      _importStatus = '正在解压...';
      notifyListeners();

      // 监听原生进度
      progressSub = _progressChannel.receiveBroadcastStream().listen(
        (event) async {
          if (event is Map) {
            final type = event['type'] as String?;
            if (type == 'progress') {
              _importProgress = (event['progress'] as num?)?.toDouble() ?? 0;
              _importCurrentFile = event['file'] as String? ?? '';
              _importStatus = '正在解压: ${_importCurrentFile} (${(_importProgress * 100).toStringAsFixed(0)}%)';
              notifyListeners();
            } else if (type == 'done') {
              final prefillPath = event['prefill'] as String? ?? '';
              final decodePath = event['decode'] as String? ?? '';
              final tokenizerPath = event['tokenizer'] as String? ?? '';

              if (prefillPath.isEmpty || decodePath.isEmpty || tokenizerPath.isEmpty) {
                completer.completeError(Exception('.TG 文件缺少必要组件'));
                return;
              }

              // 读取 manifest 获取模型名
              final manifestPath = event['manifest'] as String? ?? '';
              String name = modelName;
              if (manifestPath.isNotEmpty) {
                try {
                  final manifestContent = await File(manifestPath).readAsString();
                  final manifestJson = jsonDecode(manifestContent) as Map<String, dynamic>;
                  final metaName = manifestJson['name'] as String?;
                  if (metaName != null && metaName.isNotEmpty) name = metaName;
                } catch (_) {}
              }

              final info = ModelInfo(
                id: const Uuid().v4(),
                name: name,
                path: prefillPath,
                decodePath: decodePath,
                tokenizerPath: tokenizerPath,
                addedAt: DateTime.now(),
              );

              _models.add(info);
              _current ??= info;
              await _save();
              completer.complete(info);
            } else if (type == 'error') {
              completer.completeError(Exception(event['error'] ?? '解压失败'));
            } else if (type == 'cancelled') {
              completer.completeError(Exception('已取消'));
            }
          }
        },
        onError: (e) {
          completer.completeError(e);
        },
      );

      // 调用原生解压
      await _importChannel.invokeMethod('extractTg', {
        'tgPath': tgPath,
        'outDir': modelsDir.path,
      });

      // 超时保护：大文件解压最多等 30 分钟
      final result = await completer.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw Exception('解压超时（30分钟）'),
      );
      _importProgress = 1.0;
      _importStatus = '导入完成';
      _error = null;
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      progressSub?.cancel();
      _importing = false;
      _busy = false;
      notifyListeners();
    }
  }

  Future<ModelInfo?> addTgaiModel(String prefillPath) async {
    _busy = true;
    notifyListeners();
    try {
      final dir = p.dirname(prefillPath);
      final baseName = p.basenameWithoutExtension(prefillPath).replaceAll('_prefill', '');
      final decodePath = p.join(dir, '${baseName}_decode.ptl');
      final tokenizerPath = p.join(dir, 'tokenizer.json');

      if (!await File(prefillPath).exists()) throw Exception('prefill 文件不存在');
      if (!await File(decodePath).exists()) throw Exception('同目录下未找到 ${baseName}_decode.ptl');
      if (!await File(tokenizerPath).exists()) throw Exception('同目录下未找到 tokenizer.json');

      final destPrefill = await _copyToModelsDir(prefillPath);
      final destDecode = await _copyToModelsDir(decodePath);
      final destTokenizer = await _copyToModelsDir(tokenizerPath);

      final info = ModelInfo(
        id: const Uuid().v4(),
        name: '$baseName.ptl',
        path: destPrefill,
        decodePath: destDecode,
        tokenizerPath: destTokenizer,
        addedAt: DateTime.now(),
      );
      _models.add(info);
      _current ??= info;
      await _save();
      _error = null;
      return info;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String> _copyToModelsDir(String originalPath) async {
    final docs = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(docs.path, 'tg_chat', 'models'));
    await modelsDir.create(recursive: true);
    final name = p.basename(originalPath);
    final dest = p.join(modelsDir.path, name);
    await File(originalPath).copy(dest);
    return dest;
  }

  Future<void> removeModel(String id) async {
    final idx = _models.indexWhere((m) => m.id == id);
    if (idx < 0) return;
    final m = _models[idx];
    for (final path in [m.path, m.decodePath, m.tokenizerPath]) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _models.removeAt(idx);
    if (_current?.id == id) _current = _models.isNotEmpty ? _models.first : null;
    await _save();
    notifyListeners();
  }

  void selectModel(String id) {
    _current = _models.where((m) => m.id == id).firstOrNull;
    _save();
    notifyListeners();
  }

  Future<void> cancelImport() async {
    await _importChannel.invokeMethod('cancelImport');
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
