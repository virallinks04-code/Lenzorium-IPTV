import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'focusable.dart';

class Clock extends StatefulWidget {
  const Clock({super.key, this.size = 22});
  final double size;
  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  late Timer _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 15), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(hm(DateTime.now()), style: TextStyle(fontSize: widget.size, fontWeight: FontWeight.w500));
}

/// Standard screen frame: title row with clock, then content.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({super.key, required this.title, this.subtitle, required this.child, this.actions = const [], this.hint});
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return BackHandler(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 16 : 40, compact ? 12 : 28, compact ? 16 : 40, compact ? 8 : 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (compact)
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                  ),
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text(title, style: headline(compact ? 24 : 30)),
                    if (subtitle != null) ...[
                      const SizedBox(width: 16),
                      Flexible(
                          child: Text(subtitle!,
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, color: LzColors.muted))),
                    ],
                  ]),
                ),
                ...actions.expand((a) => [a, const SizedBox(width: 12)]),
                if (hint != null && !compact) ...[
                  Text(hint!, style: const TextStyle(fontSize: 15, color: LzColors.muted)),
                  const SizedBox(width: 20),
                ],
                if (!compact) const Clock(),
              ]),
              SizedBox(height: compact ? 12 : 20),
              Expanded(child: child),
            ]),
          ),
        ),
      ),
    );
  }
}

/// List row used for categories and settings menus.
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.label,
    this.trailing,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
    this.icon,
    this.focusNode,
    this.onFocus,
  });

  final String label;
  final String? trailing;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;
  final IconData? icon;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) => Focusable(
        autofocus: autofocus,
        focusNode: focusNode,
        onSelect: onSelect,
        radius: 10,
        onFocusChange: (f) {
          if (f) onFocus?.call();
        },
        builder: (_, focused) => Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? LzColors.surface2 : (focused ? LzColors.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 18, color: LzColors.muted), const SizedBox(width: 10)],
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16,
                      color: selected ? LzColors.text : LzColors.textSoft,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 14, color: LzColors.muted)),
          ]),
        ),
      );
}

/// Asks for the parental PIN. Returns true when it matches.
Future<bool> askPin(BuildContext context, {String title = 'Enter parental PIN'}) async {
  final app = context.read<AppState>();
  if (!app.settings.hasPin) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => PinDialog(title: title, check: (pin) => pin == app.settings.parentalPin),
  );
  return ok ?? false;
}

/// Number-pad PIN entry that works with a remote (digits or D-pad).
class PinDialog extends StatefulWidget {
  const PinDialog({super.key, required this.title, this.check, this.length = 4});
  final String title;
  final bool Function(String pin)? check;
  final int length;
  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  String _pin = '';
  bool _wrong = false;

  void _tap(String d) {
    if (_pin.length >= widget.length) return;
    setState(() {
      _pin += d;
      _wrong = false;
    });
    if (_pin.length == widget.length) {
      if (widget.check == null) {
        Navigator.of(context).pop(_pin);
      } else if (widget.check!(_pin)) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _wrong = true;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '⌫', '0', '✕'];
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title, style: headline(22)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.length,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? LzColors.text : Colors.transparent,
                    border: Border.all(color: LzColors.muted, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 22,
              child: _wrong ? const Text('Wrong PIN, try again', style: TextStyle(color: Color(0xFFFF8A8A))) : null,
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: [
                for (var i = 0; i < keys.length; i++)
                  Focusable(
                    autofocus: i == 0,
                    radius: 10,
                    semanticLabel: keys[i] == '⌫' ? 'Delete' : (keys[i] == '✕' ? 'Cancel' : keys[i]),
                    onSelect: () {
                      final k = keys[i];
                      if (k == '⌫') {
                        if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
                      } else if (k == '✕') {
                        Navigator.of(context).pop(widget.check == null ? null : false);
                      } else {
                        _tap(k);
                      }
                    },
                    builder: (_, f) => Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: f ? LzColors.surface3 : LzColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(keys[i], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Small helper to show a message at the bottom of the screen.
void toast(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}
