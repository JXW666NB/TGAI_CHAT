import 'dart:async';
import 'package:flutter/services.dart';

class PytorchService {
  static const MethodChannel _channel = MethodChannel('tg_chat/inference');

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  int nCtx = 0;

  Future<void> loadModel({
    required String modelPath,
    required String tokenizerPath,
    required int nCtx,
  }) async {
    await unloadModel();
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('loadModel', {
      'modelPath': modelPath,
      'tokenizerPath': tokenizerPath,
      'nCtx': nCtx,
    });
    if (result == null || result['success'] != true) {
      throw Exception(result?['error'] ?? '加载模型失败');
    }
    _isLoaded = true;
    this.nCtx = result['nCtx'] as int? ?? nCtx;
  }

  Future<void> unloadModel() async {
    if (!_isLoaded) return;
    await _channel.invokeMethod('unloadModel');
    _isLoaded = false;
  }

  Future<int> countTokens(String text) async {
    if (!_isLoaded) throw Exception('model not loaded');
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('countTokens', {
      'text': text,
    });
    return result?['count'] as int? ?? 0;
  }

  Future<void> stopGenerate() async {
    await _channel.invokeMethod('stopGenerate');
  }

  Stream<String> generate(
    String prompt, {
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    int maxTokens = 256,
    double repeatPenalty = 1.1,
    int repeatLastN = 64,
    int prefillWindow = 64,
    int decodeWindow = 16,
  }) {
    if (!_isLoaded) throw Exception('model not loaded');

    final eventChannel = EventChannel('tg_chat/generate');

    // 先创建 StreamController 并建立 EventChannel 监听，再调用 startGenerate
    // 避免原生线程在 Dart 监听就绪前发送事件导致崩溃
    final controller = StreamController<String>();

    late StreamSubscription<dynamic> sub;
    sub = eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          if (event['type'] == 'token') {
            controller.add(event['text'] as String);
          } else if (event['type'] == 'error') {
            controller.addError(Exception(event['error']));
          } else if (event['type'] == 'done') {
            controller.close();
          }
        }
      },
      onError: (e) {
        controller.addError(e);
      },
      onDone: () {
        controller.close();
      },
      cancelOnError: true,
    );

    // 监听建立后再启动推理
    _channel.invokeMethod('startGenerate', {
      'prompt': prompt,
      'temperature': temperature,
      'topK': topK,
      'topP': topP,
      'maxTokens': maxTokens,
      'repeatPenalty': repeatPenalty,
      'repeatLastN': repeatLastN,
      'prefillWindow': prefillWindow,
      'decodeWindow': decodeWindow,
    });

    controller.onCancel = () {
      sub.cancel();
      _channel.invokeMethod('stopGenerate');
    };

    return controller.stream;
  }
}
