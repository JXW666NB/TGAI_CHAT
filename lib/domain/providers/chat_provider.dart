import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/config.dart';
import '../../data/session_store.dart';
import '../../services/pytorch_service.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import 'models_provider.dart';
import 'settings_provider.dart';

class ChatProvider extends ChangeNotifier {
  final SessionStore _store = SessionStore();
  final PytorchService _pytorch = PytorchService();

  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  bool _isLoadingModel = false;
  String? _error;
  StreamSubscription<String>? _genSub;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  ChatSession? get currentSession => _currentSession;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  bool get isLoadingModel => _isLoadingModel;
  String? get error => _error;
  bool get modelLoaded => _pytorch.isLoaded;

  Future<void> init() async {
    _sessions = await _store.loadSessions();
    if (_sessions.isNotEmpty) await selectSession(_sessions.first.id);
    notifyListeners();
  }

  Future<void> createSession() async {
    final session = ChatSession(
      id: const Uuid().v4(),
      title: '新会话',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _sessions.insert(0, session);
    await _store.saveSessions(_sessions);
    await selectSession(session.id);
  }

  Future<void> selectSession(String id) async {
    if (_currentSession?.id == id) return;
    _currentSession = _sessions.where((s) => s.id == id).firstOrNull;
    if (_currentSession == null) return;
    _messages = await _store.loadMessages(id);
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await _store.deleteSession(id);
    _sessions.removeWhere((s) => s.id == id);
    if (_currentSession?.id == id) {
      _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
      _messages = _currentSession != null ? await _store.loadMessages(_currentSession!.id) : [];
    }
    notifyListeners();
  }

  Future<void> renameSession(String id, String title) async {
    final s = _sessions.where((s) => s.id == id).firstOrNull;
    if (s == null) return;
    s.title = title;
    s.updatedAt = DateTime.now();
    await _store.saveSessions(_sessions);
    notifyListeners();
  }

  Future<void> clearCurrentSession() async {
    if (_currentSession == null) return;
    _messages.clear();
    await _store.saveMessages(_currentSession!.id, _messages);
    notifyListeners();
  }

  Future<void> ensureModelLoaded(ModelsProvider models, SettingsProvider settings) async {
    final model = models.current;
    if (model == null) throw Exception('请先在"模型"页选择一个模型');
    if (_pytorch.isLoaded) return;

    _isLoadingModel = true;
    _error = null;
    notifyListeners();
    try {
      await _pytorch.loadModel(
        modelPath: model.path,
        tokenizerPath: model.tokenizerPath,
        nCtx: settings.contextLength,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoadingModel = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text, SettingsProvider settings, ModelsProvider models) async {
    if (text.trim().isEmpty) return;
    if (_currentSession == null) await createSession();

    final userMsg = ChatMessage(
      id: const Uuid().v4(),
      sessionId: _currentSession!.id,
      role: MessageRole.user,
      content: text.trim(),
      createdAt: DateTime.now(),
    );
    _messages.add(userMsg);
    _currentSession!.updatedAt = DateTime.now();
    await _saveState();

    await ensureModelLoaded(models, settings);

    final assistantMsg = ChatMessage(
      id: const Uuid().v4(),
      sessionId: _currentSession!.id,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      isGenerating: true,
    );
    _messages.add(assistantMsg);
    _isGenerating = true;
    _error = null;
    notifyListeners();

    final prompt = _buildPrompt(text.trim(), settings);

    final stream = _pytorch.generate(
      prompt,
      temperature: settings.temperature,
      topK: settings.topK,
      topP: settings.topP,
      maxTokens: settings.maxTokens,
      repeatPenalty: settings.repeatPenalty,
      repeatLastN: settings.repeatLastN,
    );

    _genSub = stream.listen(
      (piece) {
        final idx = _messages.indexWhere((m) => m.id == assistantMsg.id);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(content: _messages[idx].content + piece);
          notifyListeners();
        }
      },
      onError: (e) {
        _error = e.toString();
        _finishGeneration(assistantMsg.id);
      },
      onDone: () => _finishGeneration(assistantMsg.id),
    );
  }

  void _finishGeneration(String assistantId) {
    _genSub?.cancel();
    _genSub = null;
    final idx = _messages.indexWhere((m) => m.id == assistantId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(isGenerating: false);
    }
    _isGenerating = false;
    _updateTitleFromFirstMessage();
    _saveState();
    notifyListeners();
  }

  void _updateTitleFromFirstMessage() {
    if (_currentSession == null) return;
    final firstUser = _messages.where((m) => m.role == MessageRole.user).firstOrNull;
    if (firstUser != null && _currentSession!.title == '新会话') {
      _currentSession!.title = firstUser.content.length > 20
          ? '${firstUser.content.substring(0, 20)}...'
          : firstUser.content;
    }
  }

  String _buildPrompt(String latestInput, SettingsProvider settings) {
    final buffer = StringBuffer();
    if (settings.systemPrompt.isNotEmpty) {
      buffer.writeln(settings.systemPrompt);
    }

    final historyMessages = _messages.where((m) => m.role != MessageRole.system).toList();
    final historyBuffer = StringBuffer();
    for (final m in historyMessages) {
      if (m.role == MessageRole.user) {
        historyBuffer.write('${settings.userPrefix}${m.content}\n');
      } else if (m.role == MessageRole.assistant) {
        historyBuffer.write('${settings.assistantPrefix}${m.content}\n');
      }
    }

    String history = historyBuffer.toString();
    if (history.length > settings.contextLength * 3) {
      history = history.substring(max(0, history.length - settings.contextLength * 3));
    }

    String prompt = settings.promptTemplate;
    prompt = prompt.replaceAll('{history}', history);
    prompt = prompt.replaceAll('{userPrefix}', settings.userPrefix);
    prompt = prompt.replaceAll('{assistantPrefix}', settings.assistantPrefix);
    prompt = prompt.replaceAll('{input}', latestInput);
    prompt = prompt.replaceAll('{system}', settings.systemPrompt);

    if (settings.promptTemplate.contains('{history}')) {
      buffer.write(prompt);
    } else {
      buffer.write(history);
      buffer.write(prompt);
    }

    return buffer.toString();
  }

  Future<void> _saveState() async {
    if (_currentSession == null) return;
    await _store.saveSessions(_sessions);
    await _store.saveMessages(_currentSession!.id, _messages);
  }

  Future<void> stopGeneration() async {
    await _genSub?.cancel();
    _genSub = null;
    _isGenerating = false;
    await _pytorch.stopGenerate();
    final idx = _messages.lastIndexWhere((m) => m.isGenerating);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(isGenerating: false);
    }
    await _saveState();
    notifyListeners();
  }

  Future<void> unloadModel() async {
    await _pytorch.unloadModel();
    notifyListeners();
  }
}
