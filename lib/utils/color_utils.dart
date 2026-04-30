import 'package:flutter/material.dart';

/// Compute HSL background color from a hash of the full name.
/// Works for any Unicode name (Chinese, emoji, numbers, ASCII).
/// Returns a distinct pastel color distributed across the hue spectrum.
Color avatarColor(String name) {
  if (name.isEmpty) return const Color(0xFF0078D7); // fallback blue
  // djb2-style hash of the full name string
  var hash = 5381;
  for (var i = 0; i < name.length; i++) {
    hash = ((hash << 5) + hash + name.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1.0, hue, 0.75, 0.65).toColor();
}

/// Returns a readable text color for a given background.
/// White on dark backgrounds (luminance < 0.5), black87 on light ones.
/// Consistent algorithm — not affected by isActive or theme.
Color textOnBg(Color bg) {
  return bg.computeLuminance() < 0.5 ? Colors.white : Colors.black87;
}
