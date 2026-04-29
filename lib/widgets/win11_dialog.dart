import 'package:flutter/material.dart';
import '../config/constants.dart';

/// A modern Windows 11-style dialog.
///
/// Features:
/// - Mica-like semi-transparent backdrop with blur
/// - Clean rounded card (8px corners)
/// - Subtle elevation shadow
/// - Accent-colored primary button
/// - Minimal, airy layout
class Win11Dialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmText;
  final String cancelText;
  final Color? accentColor;
  final Widget? icon;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const Win11Dialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmText = 'Confirm',
    this.cancelText = 'Cancel',
    this.accentColor,
    this.icon,
    this.onConfirm,
    this.onCancel,
  });

  /// Show the dialog and return true if confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    Color? accentColor,
    Widget? icon,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => Win11Dialog(
        title: title,
        content: content,
        confirmText: confirmText,
        cancelText: cancelText,
        accentColor: accentColor,
        icon: icon,
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    ).then((v) => v ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentColor ?? AppConstants.primaryBlue;
    final surfaceColor = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryText = isDark ? Colors.white70 : Colors.black54;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          onCancel?.call();
        }
      },
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 480),
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title area
                  if (icon != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 28, bottom: 4),
                      child: Center(child: icon),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      icon != null ? 8 : 28,
                      24,
                      4,
                    ),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  // Content area
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Text(
                      content,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ),
                  // Divider
                  Container(
                    height: 0.5,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  // Buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Cancel button — ghost style
                        _Win11Button(
                          label: cancelText,
                          onTap: onCancel,
                        ),
                        const SizedBox(width: 8),
                        // Confirm button — accent filled
                        _Win11Button(
                          label: confirmText,
                          accent: accent,
                          filled: true,
                          onTap: onConfirm,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A clean Win11-style button widget.
class _Win11Button extends StatefulWidget {
  final String label;
  final bool filled;
  final Color? accent;
  final VoidCallback? onTap;

  const _Win11Button({
    required this.label,
    this.filled = false,
    this.accent,
    this.onTap,
  });

  @override
  State<_Win11Button> createState() => _Win11ButtonState();
}

class _Win11ButtonState extends State<_Win11Button> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.filled
        ? (widget.accent ?? AppConstants.primaryBlue)
        : Colors.transparent;
    final fg = widget.filled
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);
    final hoverBg = widget.filled
        ? bg.withValues(alpha: 0.85)
        : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: _hovering ? hoverBg : bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.filled
                ? null
                : Border.all(
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: widget.filled ? FontWeight.w600 : FontWeight.w400,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
