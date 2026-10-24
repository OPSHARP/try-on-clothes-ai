import 'package:flutter/material.dart';

/// App color palette based on the PRD specifications.
/// Primary: Green (#22C55E), Secondary: Emerald (#10B981)
class AppColors {
  AppColors._();

  // ── Primary Palette (from reference image) ──
  static const Color primary = Color(0xFF5B3FE6);
  static const Color primaryLight = Color(0xFF8B5CF6);
  static const Color primaryDark = Color(0xFF432BB3);
  static const Color secondary = Color(0xFFF97352);
  static const Color secondaryLight = Color(0xFFFB923C);
  static const Color secondaryDark = Color(0xFFEA580C);

  // ── Accent ──
  static const Color accent = Color(0xFFA78BFA);
  static const Color accentSoft = Color(0xFFEDE9FE);

  // ── Reference Hero & Button Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF5338D5), Color(0xFF7E3AED), Color(0xFFF97352)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient buttonGradient = LinearGradient(
    colors: [Color(0xFF5B3FE6), Color(0xFF8B5CF6), Color(0xFFF472B6), Color(0xFFFB7185)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient shimmerGradient = LinearGradient(
    colors: [Color(0xFF5B3FE6), Color(0xFF8B5CF6), Color(0xFF5B3FE6)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Light Theme (Soft Neumorphic Pastel) ──
  static const Color lightBackground = Color(0xFFEFF1FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFE8ECF7);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1E2432);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextTertiary = Color(0xFF94A3B8);
  static const Color lightDivider = Color(0xFFE2E8F0);
  static const Color lightIcon = Color(0xFF475569);

  // ── Dark Theme (Neumorphic Deep Navy) ──
  static const Color darkBackground = Color(0xFF0F121C);
  static const Color darkSurface = Color(0xFF171B28);
  static const Color darkSurfaceVariant = Color(0xFF1E2435);
  static const Color darkCard = Color(0xFF1A1F2E);
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);
  static const Color darkDivider = Color(0xFF2E384D);
  static const Color darkIcon = Color(0xFFCBD5E1);

  // ── Neumorphic Shadows (120 FPS optimized with const Offsets) ──
  static List<BoxShadow> neumorphic(bool isDark) {
    if (isDark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 16,
          offset: const Offset(4, 6),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(-2, -2),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF98A6C6).withValues(alpha: 0.22),
        blurRadius: 16,
        offset: const Offset(4, 6),
      ),
      const BoxShadow(
        color: Colors.white,
        blurRadius: 12,
        offset: Offset(-4, -4),
      ),
    ];
  }

  // ── Semantic ──
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // ── Glass Effect ──
  static Color glassLight = Colors.white.withValues(alpha: 0.15);
  static Color glassDark = Colors.black.withValues(alpha: 0.25);
  static Color glassBorder = Colors.white.withValues(alpha: 0.2);
}
