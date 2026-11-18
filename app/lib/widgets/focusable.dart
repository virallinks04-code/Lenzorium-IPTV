import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Keys that mean "OK" on a TV remote, keyboard or game pad.
bool isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.space ||
    k == LogicalKeyboardKey.gameButtonA;

/// Keys that open a context action (favourite) — the remote's menu key,
/// or F on a keyboard.
bool isMenuKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.contextMenu ||
    k == LogicalKeyboardKey.keyF ||
    k == LogicalKeyboardKey.gameButtonY;

/// The building block of every screen: works with D-pad (arrows + OK),
/// mouse and touch. Shows the white focus ring from the design and keeps
/// itself scrolled into view.
class Focusable extends StatefulWidget {
  const Focusable({
    super.key,
    required this.builder,
    this.onSelect,
    this.onMenu,
    this.autofocus = false,
    this.focusNode,
    this.radius = 14,
    this.scaleOnFocus = 1.0,
    this.ring = true,
    this.onFocusChange,
    this.semanticLabel,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onMenu;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final double scaleOnFocus;
  final bool ring;
  final ValueChanged<bool>? onFocusChange;
  final String? semanticLabel;

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _focused = false;
  bool _hover = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (isSelectKey(e.logicalKey) && widget.onSelect != null) {
      widget.onSelect!();
      return KeyEventResult.handled;
    }
    if (isMenuKey(e.logicalKey) && widget.onMenu != null) {
      widget.onMenu!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final show = _focused || _hover;
    return Semantics(
      button: widget.onSelect != null,
      label: widget.semanticLabel,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        onFocusChange: (f) {
          setState(() => _focused = f);
          widget.onFocusChange?.call(f);
          if (f) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 160),
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            );
          }
        },
        child: MouseRegion(
          cursor: widget.onSelect != null ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelect,
            onLongPress: widget.onMenu,
            child: AnimatedScale(
              scale: _focused ? widget.scaleOnFocus : 1.0,
              duration: const Duration(milliseconds: 120),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius + 4),
                  border: Border.all(
                    color: widget.ring && _focused
                        ? LzColors.focusRing
                        : (widget.ring && _hover ? Colors.white38 : Colors.transparent),
                    width: 3,
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: widget.builder(context, show),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum LzButtonKind { primary, secondary, ghost }

class LzButton extends StatelessWidget {
  const LzButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = LzButtonKind.secondary,
    this.autofocus = false,
    this.height = 56,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final LzButtonKind kind;
  final bool autofocus;
  final double height;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: onPressed,
      radius: 12,
      semanticLabel: label,
      builder: (context, focused) {
        final Color bg;
        final Color fg;
        switch (kind) {
          case LzButtonKind.primary:
            bg = onPressed == null ? LzColors.surface3 : LzColors.accent;
            fg = Colors.white;
          case LzButtonKind.secondary:
            bg = focused ? LzColors.surface2 : LzColors.surface;
            fg = LzColors.text;
          case LzButtonKind.ghost:
            bg = focused ? LzColors.surface2 : Colors.transparent;
            fg = LzColors.text;
        }
        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: kind == LzButtonKind.secondary ? Border.all(color: LzColors.lineStrong) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 10)],
              Text(label, style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }
}

/// Wraps a screen so Back / Escape pops it (remotes send goBack or escape).
class BackHandler extends StatelessWidget {
  const BackHandler({super.key, required this.child, this.onBack});
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _back(context),
        const SingleActivator(LogicalKeyboardKey.goBack): () => _back(context),
        const SingleActivator(LogicalKeyboardKey.browserBack): () => _back(context),
      },
      child: child,
    );
  }

  void _back(BuildContext context) {
    if (onBack != null) {
      onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}
