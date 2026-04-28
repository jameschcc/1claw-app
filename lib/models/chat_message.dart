class ChatMessage {
  final String id;
  final String profileId;
  final String content;
  final String role; // "user" or "agent"
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.profileId,
    required this.content,
    required this.role,
    DateTime? timestamp,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'profile_id': profileId,
        'content': content,
        'role': role,
        'timestamp': timestamp.toIso8601String(),
  };

  bool get isUser => role == 'user';
  bool get isAgent => role == 'agent';
}
