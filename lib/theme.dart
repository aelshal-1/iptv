import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  static const bg = Color(0xFF060709);
  static const surface = Color(0xFF0E0F13);
  static const card = Color(0xFF15171C);
  static const text = Color(0xFFF5F3EF);
  static const dim = Color(0xB3F5F3EF);
  static const dimmer = Color(0x80F5F3EF);
  static const gold = Color(0xFFE7C27D);
  static const onGold = Color(0xFF14110A);
  static const red = Color(0xFFE5484D);
  static const glass = Color(0x0FFFFFFF);
  static const glassBorder = Color(0x1AFFFFFF);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.gold,
      onPrimary: C.onGold,
      secondary: C.gold,
      surface: C.surface,
      onSurface: C.text,
    ),
  );
  String? family;
  try {
    family = GoogleFonts.readexPro().fontFamily;
  } catch (_) {}
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: family, bodyColor: C.text, displayColor: C.text),
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, elevation: 0, scrolledUnderElevation: 0, foregroundColor: C.text),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0B0C10),
      indicatorColor: C.gold.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.gold : C.dim)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 12, color: s.contains(WidgetState.selected) ? C.gold : C.dim)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x66000000),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.glassBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.glassBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.gold, width: 2)),
      hintStyle: const TextStyle(color: C.dimmer),
      labelStyle: const TextStyle(color: C.dim),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.gold,
        foregroundColor: C.onGold,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: Color(0x29FFFFFF)),
        backgroundColor: const Color(0x14FFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: Color(0xF014161C), contentTextStyle: TextStyle(color: C.text), behavior: SnackBarBehavior.floating),
    dividerColor: C.glassBorder,
  );
}

class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 22});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(radius), border: Border.all(color: C.glassBorder)),
        child: child,
      );
}

/// Network image with a dark placeholder that shows the title if the image fails.
class NetImg extends StatelessWidget {
  final String? url;
  final String label;
  final BoxFit fit;
  const NetImg(this.url, {super.key, this.label = '', this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) {
    final ph = Container(
      color: C.card,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(label, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.dimmer, fontSize: 13)),
    );
    if (url == null || url!.isEmpty) return ph;
    return Image.network(url!, fit: fit, errorBuilder: (_, __, ___) => ph, loadingBuilder: (c, w, p) => p == null ? w : ph);
  }
}

/// The app mark: gold keyhole arch with a play symbol.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Image.asset('assets/logo.png', width: size, height: size, filterQuality: FilterQuality.medium);
}
