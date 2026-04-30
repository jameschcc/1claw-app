import 'package:flutter/painting.dart';

class AgentProfile {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final String color;
  bool online;
  String status;   // "working" | "free" | "idle" | "starting"
  int tasksQueue;
  bool isPinned;

  AgentProfile({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    this.color = '#0078D7',
    this.online = false,
    this.status = 'free',
    this.tasksQueue = 0,
    this.isPinned = false,
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

  /// Generate avatar color from name using HSL formula.
  /// h = (firstLowercaseAscii - '0') / ('z' - '0') * 360
  /// s = 0.75, l = 0.6
  int get colorValue {
    final first = name.isNotEmpty ? name.toLowerCase().codeUnitAt(0) : 97;
    final clamped = (first >= 97 && first <= 122) ? first : 97; // 'a' – 'z'
    final h = (clamped - 48) / (122 - 48) * 360;
    return HSLColor.fromAHSL(1.0, h, 0.75, 0.6).toColor().toARGB32();
  }
}
