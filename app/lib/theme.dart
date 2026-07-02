import 'package:flutter/material.dart';

/// 금고 디자인 토큰 — 다크 프리미엄.
abstract class G {
  static const bg = Color(0xFF0A0E14);
  static const surface = Color(0xFF111823);
  static const surfaceHi = Color(0xFF17212E);
  static const field = Color(0xFF0D141D);
  static const border = Color(0x16FFFFFF);
  static const mint = Color(0xFF2EE6A8);
  static const mintDeep = Color(0xFF0FBF87);
  static const onMint = Color(0xFF05271B);
  static const text = Color(0xFFE8EEF4);
  static const sub = Color(0xFF8C99A8);
  static const faint = Color(0xFF5A6675);
  static const danger = Color(0xFFFF6B6B);
  static const amber = Color(0xFFFFC24B);

  /// 모노그램 아바타용 그라데이션 팔레트 — 제목 해시로 선택.
  static const avatarGradients = [
    [Color(0xFF2EE6A8), Color(0xFF0E9F6E)],
    [Color(0xFF5EA2FF), Color(0xFF2D6BDF)],
    [Color(0xFFB58CFF), Color(0xFF7C4DDB)],
    [Color(0xFFFF8FA3), Color(0xFFE0526F)],
    [Color(0xFFFFC24B), Color(0xFFE08E1B)],
    [Color(0xFF4DD6E0), Color(0xFF1FA3B4)],
    [Color(0xFFFF9E6B), Color(0xFFE06A2E)],
    [Color(0xFF9BE05A), Color(0xFF5FA82A)],
  ];

  static List<Color> avatarGradient(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return avatarGradients[h % avatarGradients.length];
  }
}

ThemeData buildGeumgoTheme() {
  const scheme = ColorScheme.dark(
    primary: G.mint,
    onPrimary: G.onMint,
    secondary: G.mint,
    onSecondary: G.onMint,
    surface: G.surface,
    onSurface: G.text,
    surfaceContainerHighest: G.surfaceHi,
    onSurfaceVariant: G.sub,
    outline: G.faint,
    outlineVariant: G.border,
    error: G.danger,
    onError: Color(0xFF2B0808),
    primaryContainer: Color(0xFF123B2E),
    onPrimaryContainer: G.mint,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Pretendard',
    scaffoldBackgroundColor: G.bg,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: G.text,
      displayColor: G.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: G.text,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: G.sub),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: G.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: G.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: G.field,
      hintStyle: const TextStyle(color: G.faint),
      labelStyle: const TextStyle(color: G.sub),
      floatingLabelStyle: const TextStyle(color: G.mint),
      prefixIconColor: G.faint,
      suffixIconColor: G.faint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: G.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: G.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: G.mint, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: G.mint,
        foregroundColor: G.onMint,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: G.mint),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: G.sub),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: G.mint,
      foregroundColor: G.onMint,
      elevation: 4,
      extendedTextStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: G.surfaceHi,
      contentTextStyle: const TextStyle(
        fontFamily: 'Pretendard',
        color: G.text,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: G.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: G.surfaceHi,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: G.text,
      ),
    ),
    dividerTheme: const DividerThemeData(color: G.border, thickness: 1),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: G.surfaceHi,
      side: const BorderSide(color: G.border),
      labelStyle: const TextStyle(
        fontFamily: 'Pretendard',
        color: G.sub,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: G.mint,
      inactiveTrackColor: G.surfaceHi,
      thumbColor: G.mint,
      overlayColor: G.mint.withValues(alpha: 0.12),
      valueIndicatorColor: G.surfaceHi,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? G.onMint : G.faint),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? G.mint : G.surfaceHi),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? G.mint : G.border),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: G.mint),
    listTileTheme: const ListTileThemeData(
      iconColor: G.sub,
      textColor: G.text,
    ),
  );
}

/// 은은한 배경 글로우 (잠금 화면 등에서 사용).
class GlowBackdrop extends StatelessWidget {
  const GlowBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        top: -140,
        left: -100,
        child: _glow(G.mint.withValues(alpha: 0.13), 420),
      ),
      Positioned(
        bottom: -160,
        right: -120,
        child: _glow(const Color(0xFF2D6BDF).withValues(alpha: 0.10), 460),
      ),
      child,
    ]);
  }

  Widget _glow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// 제목 해시 색 그라데이션 모노그램 아바타.
class Monogram extends StatelessWidget {
  const Monogram({super.key, required this.seed, this.size = 44});

  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = G.avatarGradient(seed);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        seed.isEmpty ? '?' : seed.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}
