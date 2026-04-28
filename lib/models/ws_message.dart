class WsMessage {
  final String type;
  final String? profileId;
  final String? content;
  final String? id;
  final String? timestamp;
  final String? message;
  final String? code;
  final List<dynamic>? profiles;

  WsMessage({
    required this.type,
    this.profileId,
    this.content,
    this.id,
    this.timestamp,
    this.message,
    this.code,
    this.profiles,
  });

  factory WsMessage.fromJson(Map<String, dynamic> json) {
    return WsMessage(
      type: json['type'] as String? ?? '',
      profileId: json['profile_id'] as String?,
      content: json['content'] as String?,
      id: json['id'] as String?,
      timestamp: json['timestamp'] as String?,
      message: json['message'] as String?,
      code: json['code'] as String?,
      profiles: json['profiles'] as List<dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (profileId != null) 'profile_id': profileId,
        if (content != null) 'content': content,
        if (id != null) 'id': id,
      };
}
