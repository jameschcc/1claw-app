import 'package:flutter/material.dart';

/// Show a subtle floating toast notification (replaces Material SnackBars).
///
/// Centered near the top, fades in/out gently. Auto-dismisses after [duration].
void showToast(BuildContext context, String message, {Duration? duration}) {
  OverlayEntry? entry;
  entry = OverlayEntry(
    builder: (_) => _ToastWidget(
      message: message,
      duration: duration ?? const Duration(seconds: 2),
      onDismiss: () => entry?.remove(),
    ),
  );
  Overlay.of(context).insert(entry);
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final Duration duration;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
    Future.delayed(widget.duration, () {
      if (mounted) {
        _ctrl.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black87.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
