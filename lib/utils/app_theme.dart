import 'package:flutter/material.dart';

class AppTheme {
  static const double fontSizeSmall = 16.0;
  static const double fontSizeMedium = 20.0;
  static const double fontSizeLarge = 24.0;
  static const double fontSizeXLarge = 28.0;
  static const double fontSizeTitle = 32.0;
  static const double fontSizeHuge = 36.0;

  static const double minTouchTarget = 56.0;

  // 라이트 색상
  static const Color primaryColor = Color(0xFF1A237E);
  static const Color backgroundColor = Color(0xFFFAFAFA);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF888888);
  static const Color dividerColor = Color(0xFFEEEEEE);
  static const Color dangerColor = Color(0xFFF44336);

  // 다크 색상
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color darkTextPrimary = Color(0xFFF5F5F5);
  static const Color darkTextSecondary = Color(0xFF9E9E9E);
  static const Color darkDivider = Color(0xFF2C2C2C);
  static const Color darkSurface = Color(0xFF2A2A2A);

  static Color hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  // 라이트 테마
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(size: 28),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, minTouchTarget),
          textStyle: const TextStyle(
            fontSize: fontSizeMedium,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: fontSizeMedium),
        hintStyle: const TextStyle(fontSize: fontSizeMedium, color: Color(0xFFBBBBBB)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        sizeConstraints: BoxConstraints.tightFor(width: 64, height: 64),
        iconSize: 32,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: fontSizeHuge, fontWeight: FontWeight.w800, color: textPrimary),
        headlineMedium: TextStyle(fontSize: fontSizeTitle, fontWeight: FontWeight.w700, color: textPrimary),
        titleLarge: TextStyle(fontSize: fontSizeXLarge, fontWeight: FontWeight.w700, color: textPrimary),
        titleMedium: TextStyle(fontSize: fontSizeLarge, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: fontSizeMedium, fontWeight: FontWeight.w500, color: textPrimary),
        bodyMedium: TextStyle(fontSize: fontSizeMedium, color: textSecondary),
        labelLarge: TextStyle(fontSize: fontSizeMedium, fontWeight: FontWeight.w700),
      ),
    );
  }

  // 다크 테마
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
      ).copyWith(
        surface: darkCard,
        onSurface: darkTextPrimary,
      ),
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkCard,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        iconTheme: IconThemeData(size: 28, color: darkTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, minTouchTarget),
          textStyle: const TextStyle(
            fontSize: fontSizeMedium,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF444444), width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF444444), width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: fontSizeMedium, color: darkTextPrimary),
        hintStyle: const TextStyle(fontSize: fontSizeMedium, color: darkTextSecondary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        sizeConstraints: BoxConstraints.tightFor(width: 64, height: 64),
        iconSize: 32,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: fontSizeHuge, fontWeight: FontWeight.w800, color: darkTextPrimary),
        headlineMedium: TextStyle(fontSize: fontSizeTitle, fontWeight: FontWeight.w700, color: darkTextPrimary),
        titleLarge: TextStyle(fontSize: fontSizeXLarge, fontWeight: FontWeight.w700, color: darkTextPrimary),
        titleMedium: TextStyle(fontSize: fontSizeLarge, fontWeight: FontWeight.w600, color: darkTextPrimary),
        bodyLarge: TextStyle(fontSize: fontSizeMedium, fontWeight: FontWeight.w500, color: darkTextPrimary),
        bodyMedium: TextStyle(fontSize: fontSizeMedium, color: darkTextSecondary),
        labelLarge: TextStyle(fontSize: fontSizeMedium, fontWeight: FontWeight.w700, color: darkTextPrimary),
      ),
    );
  }
}

/// 카테고리 아이콘 위젯 - 이모지(문자) 또는 이미지 자산을 자동 판별하여 렌더링
class CategoryIcon extends StatelessWidget {
  final String icon;
  final double size;

  const CategoryIcon({super.key, required this.icon, this.size = 32});

  bool get _isAsset => icon.startsWith('assets/');

  @override
  Widget build(BuildContext context) {
    if (_isAsset) {
      return Image.asset(
        icon,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) =>
            Text('📁', style: TextStyle(fontSize: size * 0.8)),
      );
    }
    return Text(icon, style: TextStyle(fontSize: size));
  }
}