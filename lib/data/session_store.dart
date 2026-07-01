import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../domain/models/chat_message.dart';
import '../domain/models/chat_session.dart';

class SessionStore {
  static final SessionStore _instance = SessionStore._internal();
  factory SessionStore() => _instance;
  SessionStore._internal();

  Directory? _root;

  Future<Directory> get root async {
    _root ??= Directory(p.join((await getApplicationDocumentsDirectory()).path, 'tg_chat'));
    if (!await _root!.exists()) await _root!.create(recursive: true);
    return _root!;
  }

  Future<File> get _sessionsFile async => File(p.join((await root).path, 'sessions.json'));

  Future<File> _messagesFile(String sessionId) async =>
      File(p.join((await root).path, 'messages_$sessionId.json'));

  Future<List<ChatSession>> loadSessions() async {
    final file = await _sessionsFile;
    if (!await file.exists()) return [];
    final list = jsonDecode(await file.readAsString()) as List<dynamic>;
    return list.map((e) => ChatSession.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveSessions(List<ChatSession> sessions) async {
    final file = await _sessionsFile;
    final data = sessions.map((s) => s.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
  }

  Future<List<ChatMessage>> loadMessages(String sessionId) async {
    final file = await _messagesFile(sessionId);
    if (!await file.exists()) return [];
    final list = jsonDecode(await file.readAsString()) as List<dynamic>;
    return list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> saveMessages(String sessionId, List<ChatMessage> messages) async {
    final file = await _messagesFile(sessionId);
    final data = messages.map((m) => m.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> deleteSession(String sessionId) async {
    final file = await _messagesFile(sessionId);
    if (await file.exists()) await file.delete();
    final sessions = await loadSessions();
    sessions.removeWhere((s) => s.id == sessionId);
    await saveSessions(sessions);
  }
}
