import 'package:flutter/material.dart';

/// Lenzorium palette — matches the design canvas. Swap [accent] for the
/// final brand colour once Lenzorium supplies it.
class LzColors {
  static const bg = Color(0xFF0A0C10);
  static const surface = Color(0xFF141820);
  static const surface2 = Color(0xFF1C2230);
  static const surface3 = Color(0xFF262D3B);
  static const line = Color(0xFF262D3B);
  static const lineStrong = Color(0xFF343C4D);
  static const text = Color(0xFFF2F4F8);
  static const textSoft = Color(0xFFC3C9D5);
  static const muted = Color(0xFF9AA3B5);
  static const faint = Color(0xFF8A93A6);
  static const accent = Color(0xFF6B5BFF);
  static const accentText = Color(0xFFA79CFF);
  static const amber = Color(0xFFF5B547);
  static const live = Color(0xFFC8343A);
  static const focusRing = Colors.white;

  /// Stable placeholder tints for logos / posters that fail to load.
  static const tints = [
    Color(0xFF2B3A55), Color(0xFF3A2B4F), Color(0xFF4A2E3A), Color(0xFF24443D),
    Color(0xFF4A3E26), Color(0xFF2F3F4F), Color(0xFF4A3326), Color(0xFF26404A),
  ];
  static Color tintFor(String s) => tints[s.hashCode.abs() % tints.length];
}

class LzText {
  static const display = 'SpaceGrotesk';
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: LzColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: LzColors.accent,
      onPrimary: Colors.white,
      secondary: LzColors.accentText,
      surface: LzColors.surface,
      onSurface: LzColors.text,
      error: const Color(0xFFFF6B6B),
    ),
    textTheme: base.textTheme.apply(bodyColor: LzColors.text, displayColor: LzColors.text),
    focusColor: Colors.white24,
    dialogTheme: const DialogTheme(backgroundColor: LzColors.surface),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: LzColors.surface2,
      contentTextStyle: TextStyle(color: LzColors.text, fontSize: 16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LzColors.surface,
      labelStyle: const TextStyle(color: LzColors.muted),
      hintStyle: const TextStyle(color: LzColors.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: LzColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: LzColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white, width: 2)),
    ),
  );
}

TextStyle headline(double size) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: LzColors.text,
    );
