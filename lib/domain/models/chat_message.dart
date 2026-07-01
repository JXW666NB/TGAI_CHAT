enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final bool isGenerating;

  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isGenerating = false,
  });

  ChatMessage copyWith({
    String? id,
    String? sessionId,
    MessageRole? role,
    String? content,
    DateTime? createdAt,
    bool? isGenerating,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isGenerating: isGenerating ?? this.isGenerating,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        role: MessageRole.values.byName(json['role'] as String),
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
