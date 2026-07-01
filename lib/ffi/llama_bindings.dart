import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary _lib = Platform.isAndroid
    ? DynamicLibrary.open('libtgchat.so')
    : DynamicLibrary.executable();

typedef TgChatLoadModelC = Pointer<Void> Function(Pointer<Utf8> path, Int32 nCtx, Int32 nThreads, Pointer<Utf8> err, Int32 errSize);
typedef TgChatLoadModelDart = Pointer<Void> Function(Pointer<Utf8> path, int nCtx, int nThreads, Pointer<Utf8> err, int errSize);

final TgChatLoadModelDart tgchatLoadModel = _lib.lookupFunction<TgChatLoadModelC, TgChatLoadModelDart>('tgchat_load_model');

typedef TgChatFreeModelC = Void Function(Pointer<Void> m);
typedef TgChatFreeModelDart = void Function(Pointer<Void> m);

final TgChatFreeModelDart tgchatFreeModel = _lib.lookupFunction<TgChatFreeModelC, TgChatFreeModelDart>('tgchat_free_model');

typedef TgChatNCtxC = Int32 Function(Pointer<Void> m);
typedef TgChatNCtxDart = int Function(Pointer<Void> m);

final TgChatNCtxDart tgchatNCtx = _lib.lookupFunction<TgChatNCtxC, TgChatNCtxDart>('tgchat_n_ctx');

typedef TgChatTokenizeC = Int32 Function(Pointer<Void> m, Pointer<Utf8> text, Pointer<Int32> tokens, Int32 maxTokens, Bool addBos);
typedef TgChatTokenizeDart = int Function(Pointer<Void> m, Pointer<Utf8> text, Pointer<Int32> tokens, int maxTokens, bool addBos);

final TgChatTokenizeDart tgchatTokenize = _lib.lookupFunction<TgChatTokenizeC, TgChatTokenizeDart>('tgchat_tokenize');

typedef TgChatGenerateCallbackC = Void Function(Pointer<Utf8> piece, Pointer<Void> userData);
typedef TgChatGenerateCallbackDart = void Function(Pointer<Utf8> piece, Pointer<Void> userData);

typedef TgChatGenerateC = Int32 Function(
  Pointer<Void> m,
  Pointer<Utf8> prompt,
  Pointer<Utf8> out,
  Int32 maxOut,
  Float temp,
  Int32 topK,
  Float topP,
  Int32 maxTokens,
  Float repeatPenalty,
  Int32 repeatLastN,
  Pointer<NativeFunction<TgChatGenerateCallbackC>> callback,
  Pointer<Void> userData,
);
typedef TgChatGenerateDart = int Function(
  Pointer<Void> m,
  Pointer<Utf8> prompt,
  Pointer<Utf8> out,
  int maxOut,
  double temp,
  int topK,
  double topP,
  int maxTokens,
  double repeatPenalty,
  int repeatLastN,
  Pointer<NativeFunction<TgChatGenerateCallbackC>> callback,
  Pointer<Void> userData,
);

final TgChatGenerateDart tgchatGenerate = _lib.lookupFunction<TgChatGenerateC, TgChatGenerateDart>('tgchat_generate');
