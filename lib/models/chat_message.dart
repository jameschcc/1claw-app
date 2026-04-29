class ChatMessage {
  final String id;
  final String profileId;
  final String content;
  final String role; // "user" or "agent"
  final DateTime timestamp;
  final String? sessionId;
  final String? requestSessionId;

  ChatMessage({
    required this.id,
    required this.profileId,
    required this.content,
    required this.role,
    DateTime? timestamp,
    this.sessionId,
    this.requestSessionId,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      profileId: json['profile_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      role: json['role'] as String? ?? 'agent',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      sessionId: json['session_id'] as String?,
      requestSessionId: json['request_session_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'profile_id': profileId,
        'content': content,
        'role': role,
        'timestamp': timestamp.toIso8601String(),
        if (sessionId != null) 'session_id': sessionId,
        if (requestSessionId != null) 'request_session_id': requestSessionId,
  };

  bool get isUser => role == 'user';
  bool get isAgent => role == 'agent';
}
