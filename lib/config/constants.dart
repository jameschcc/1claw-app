import 'package:flutter/material.dart';

class AppConstants {
  // Server defaults
  static const String defaultWsUrl = 'ws://localhost:8080/ws';
  static const String defaultApiUrl = 'http://localhost:8080';

  // Theme colors
  static const Color primaryBlue = Color(0xFF0078D7);
  static const Color onlineGreen = Color(0xFF4CAF50);
  static const Color offlineGray = Color(0xFF9E9E9E);

  // Dark theme
  static const Color darkBg = Color(0xFF1E1E1E);
  static const Color darkSurface = Color(0xFF2D2D2D);
  static const Color darkCard = Color(0xFF383838);

  // Light theme
  static const Color lightBg = Color(0xFFF5F5F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);

  // Card colors for profiles
  static const Map<String, Color> profileColors = {
    'assistant': Color(0xFF0078D7), // Blue
    'writer': Color(0xFF7B1FA2), // Purple
    'coder': Color(0xFF388E3C), // Green
    'designer': Color(0xFFF57C00), // Orange
  };

  static Color getProfileColor(String id) {
    return profileColors[id] ?? primaryBlue;
  }
}
