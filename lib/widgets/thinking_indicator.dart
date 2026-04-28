import 'dart:async';
import 'package:flutter/material.dart';
import '../config/constants.dart';

/// Animated thinking indicator that cycles through ". / .. / ... / . / .. / ..."
class ThinkingIndicator extends StatefulWidget {
  final String emoji;

  const ThinkingIndicator({super.key, this.emoji = '🤖'});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  static const _frames = ['  ', '. ', '..', '...'];
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {
          _frame = (_frame + 1) % _frames.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? AppConstants.darkCard : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                widget.emoji,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Thinking bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
              minWidth: 60,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppConstants.darkCard : Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Thinking',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _frames[_frame],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black54,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
