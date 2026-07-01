import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/model_info.dart';

class ModelsProvider extends ChangeNotifier {
  final List<ModelInfo> _models = [];
  ModelInfo? _current;
  bool _busy = false;
  String? _error;

  List<ModelInfo> get models => List.unmodifiable(_models);
  ModelInfo? get current => _current;
  bool get busy => _busy;
  String? get error => _error;

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
    _busy = true;
    notifyListeners();
    try {
      final file = File(tgPath);
      if (!await file.exists()) throw Exception('文件不存在: $tgPath');

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 验证 .TG 格式
      final manifestEntry = archive.findFile('manifest.json');
      if (manifestEntry == null) {
        throw Exception('无效的 .TG 文件：缺少 manifest.json');
      }

      final manifestStr = utf8.decode(manifestEntry.content as List<int>);
      final manifest = jsonDecode(manifestStr) as Map<String, dynamic>;
      final format = manifest['format'] as String?;
      if (format != 'tgai-mobile-1') {
        throw Exception('不支持的 .TG 格式版本: $format');
      }

      final metaName = manifest['name'] as String?;
      final modelName = metaName ?? p.basenameWithoutExtension(tgPath);

      // 提取文件
      final docs = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(docs.path, 'tg_chat', 'models', modelName));
      if (await modelsDir.exists()) await modelsDir.delete(recursive: true);
      await modelsDir.create(recursive: true);

      String? destPrefill;
      String? destDecode;
      String? destTokenizer;

      for (final entry in archive) {
        if (entry.isFile) {
          final name = entry.name;
          final outPath = p.join(modelsDir.path, name);
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);

          if (name == 'prefill.ptl') {
            destPrefill = outPath;
          } else if (name == 'decode.ptl') {
            destDecode = outPath;
          } else if (name == 'tokenizer.json') {
            destTokenizer = outPath;
          }
        }
      }

      if (destPrefill == null) throw Exception('.TG 文件中缺少 prefill.ptl');
      if (destDecode == null) throw Exception('.TG 文件中缺少 decode.ptl');
      if (destTokenizer == null) throw Exception('.TG 文件中缺少 tokenizer.json');

      final info = ModelInfo(
        id: const Uuid().v4(),
        name: modelName,
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
}
