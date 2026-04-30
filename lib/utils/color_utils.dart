import 'package:flutter/material.dart';

/// Compute HSL background color from first letter of name.
/// Same logic used in UserListItem sidebar avatars.
Color avatarColor(String name) {
  final code = name.isNotEmpty ? name.codeUnitAt(0) : 65; // default 'A'
  final upper = String.fromCharCode(code).toUpperCase().codeUnitAt(0);
  final idx = (upper - 65).clamp(0, 25);
  final hue = (idx / 26.0) * 255.0;
  return HSLColor.fromAHSL(1.0, hue, 0.75, 0.75).toColor();
}
