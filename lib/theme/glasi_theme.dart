import 'package:flutter/material.dart';

class GlasiTheme {
  static ThemeData dark() {
    const accent = Color(0xFF7CFFB2);
    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF090A0D),
      cardColor: const Color(0xFF15171C),
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: const Color(0xFF111318),
      ),
      sliderTheme: const SliderThemeData(trackHeight: 4),
      navigationBarTheme: const NavigationBarThemeData(height: 72),
    );
  }
}
