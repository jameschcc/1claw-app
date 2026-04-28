class AgentProfile {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final String color;
  bool online;
  String status;   // "working" | "free" | "idle"
  int tasksQueue;

  AgentProfile({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    this.color = '#0078D7',
    this.online = false,
    this.status = 'free',
    this.tasksQueue = 0,
  });

  factory AgentProfile.fromJson(Map<String, dynamic> json) {
    return AgentProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '🤖',
      description: json['description'] as String? ?? '',
      color: json['color'] as String? ?? '#0078D7',
      online: json['online'] as bool? ?? false,
      status: json['status'] as String? ?? 'free',
      tasksQueue: json['tasks_queue'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'description': description,
        'color': color,
        'online': online,
        'status': status,
        'tasks_queue': tasksQueue,
  };

  /// Parse hex color string to Flutter Color
  int get colorValue {
    final hex = color.replaceAll('#', '');
    if (hex.length == 6) {
      return int.parse('FF$hex', radix: 16);
    }
    return 0xFF0078D7;
  }
}
