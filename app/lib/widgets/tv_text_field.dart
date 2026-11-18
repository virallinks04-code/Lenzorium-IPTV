import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// A text field that lets the D-pad move up and down out of it (Flutter's
/// default keeps arrow keys inside text fields, trapping TV remotes).
class TvTextField extends StatelessWidget {
  const TvTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.onSubmitted,
    this.focusNode,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        obscureText: obscure,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontSize: 18, color: LzColors.text),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, color: LzColors.muted),
        ),
      ),
    );
  }
}
