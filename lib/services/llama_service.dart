import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

import '../ffi/llama_bindings.dart';

class LlamaService {
  Pointer<Void>? _model;
  bool get isLoaded => _model != null && !_model!.address.isNegative;

  int nCtx = 0;

  Future<void> loadModel(String path, {int nCtx = 512, int nThreads = 4}) async {
    await _unload();
    final result = await Isolate.run(() {
      return using((arena) {
        final pathPtr = path.toNativeUtf8(allocator: arena);
        final errPtr = arena<Uint8>(1024);
        final m = tgchatLoadModel(pathPtr, nCtx, nThreads, errPtr.cast(), 1024);
        if (m == nullptr) {
          final err = errPtr.cast<Utf8>().toDartString();
          throw Exception(err);
        }
        return m.address;
      });
    });
    _model = Pointer<Void>.fromAddress(result);
    final addr = _model!.address;
    this.nCtx = await Isolate.run(() {
      final model = Pointer<Void>.fromAddress(addr);
      return tgchatNCtx(model);
    });
  }

  Future<void> _unload() async {
    if (_model != null) {
      final addr = _model!.address;
      await Isolate.run(() {
        final ptr = Pointer<Void>.fromAddress(addr);
        tgchatFreeModel(ptr);
      });
      _model = null;
    }
  }

  Future<void> unloadModel() => _unload();

  Future<int> countTokens(String text) async {
    if (_model == null) throw Exception('model not loaded');
    final addr = _model!.address;
    final maxCtx = nCtx;
    return Isolate.run(() {
      return using((arena) {
        final textPtr = text.toNativeUtf8(allocator: arena);
        final tokens = arena<Int32>(maxCtx);
        final model = Pointer<Void>.fromAddress(addr);
        return tgchatTokenize(model, textPtr, tokens, maxCtx, true);
      });
    });
  }

  Stream<String> generate(
    String prompt, {
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    int maxTokens = 256,
    double repeatPenalty = 1.1,
    int repeatLastN = 64,
  }) async* {
    if (_model == null) throw Exception('model not loaded');

    final receivePort = ReceivePort();
    final params = _GenerateParams(
      modelAddress: _model!.address,
      prompt: prompt,
      temperature: temperature,
      topK: topK,
      topP: topP,
      maxTokens: maxTokens,
      repeatPenalty: repeatPenalty,
      repeatLastN: repeatLastN,
      sendPort: receivePort.sendPort,
    );

    await Isolate.spawn(_generateIsolate, params);

    await for (final msg in receivePort) {
      if (msg is String) {
        yield msg;
      } else if (msg is _GenerateDone) {
        receivePort.close();
        if (msg.error != null) throw Exception(msg.error);
        return;
      }
    }
  }
}

class _GenerateParams {
  final int modelAddress;
  final String prompt;
  final double temperature;
  final int topK;
  final double topP;
  final int maxTokens;
  final double repeatPenalty;
  final int repeatLastN;
  final SendPort sendPort;

  _GenerateParams({
    required this.modelAddress,
    required this.prompt,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.maxTokens,
    required this.repeatPenalty,
    required this.repeatLastN,
    required this.sendPort,
  });
}

class _GenerateDone {
  final String? error;
  _GenerateDone({this.error});
}

void _generateIsolate(_GenerateParams p) {
  final model = Pointer<Void>.fromAddress(p.modelAddress);

  late final NativeCallable<TgChatGenerateCallbackC> callable;
  callable = NativeCallable<TgChatGenerateCallbackC>.listener((piece, userData) {
    final text = piece.toDartString();
    if (text.isNotEmpty) p.sendPort.send(text);
  });

  final outBuffer = calloc<Uint8>(65536);

  try {
    using((arena) {
      final promptPtr = p.prompt.toNativeUtf8(allocator: arena);
      tgchatGenerate(
        model,
        promptPtr,
        outBuffer.cast(),
        65536,
        p.temperature,
        p.topK,
        p.topP,
        p.maxTokens,
        p.repeatPenalty,
        p.repeatLastN,
        callable.nativeFunction,
        nullptr,
      );
    });
    p.sendPort.send(_GenerateDone());
  } catch (e) {
    p.sendPort.send(_GenerateDone(error: e.toString()));
  } finally {
    calloc.free(outBuffer);
    callable.close();
  }
}
