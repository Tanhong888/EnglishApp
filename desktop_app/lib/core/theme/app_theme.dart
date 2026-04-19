import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

class AppTheme {
  static const String _uiFontFamily = 'KaiTi';
  static const List<String> _uiFontFallback = <String>[
    'STKaiti',
    'KaiTi_GB2312',
    'Kaiti SC',
    'BiauKai',
    'DFKai-SB',
    'SimKai',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Segoe UI',
    'Arial',
  ];

  static TextStyle kaitiTextStyle(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? fontSize,
    double? height,
  }) {
    final seed = base ?? const TextStyle();
    return seed.copyWith(
      fontFamily: _uiFontFamily,
      fontFamilyFallback: _uiFontFallback,
      color: color,
      fontWeight: fontWeight,
      fontSize: fontSize,
      height: height,
    );
  }

  static TextStyle _sansTextStyle({
    required double fontSize,
    FontWeight? fontWeight,
    double? height,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.notoSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
    ).copyWith(
      fontFamilyFallback: const <String>[
        'Microsoft YaHei UI',
        'Segoe UI',
        'Arial',
      ],
    );
  }

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
      surface: AppColors.surface,
    ).copyWith(
      primary: AppColors.brand,
      onPrimary: Colors.white,
      primaryContainer: AppColors.brandSoft,
      onPrimaryContainer: AppColors.brandStrong,
      secondary: AppColors.warning,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.borderStrong,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.errorSoft,
      shadow: const Color(0x14000000),
      scrim: Colors.black.withValues(alpha: 0.38),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bg,
    );

    final baseTextTheme = GoogleFonts.notoSansTextTheme(base.textTheme);
    final textTheme = baseTextTheme.copyWith(
      headlineSmall: kaitiTextStyle(
        baseTextTheme.headlineSmall,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: AppColors.textPrimary,
      ),
      titleLarge: kaitiTextStyle(
        baseTextTheme.titleLarge,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: AppColors.textPrimary,
      ),
      titleMedium: _sansTextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.35,
        color: AppColors.textPrimary,
      ),
      titleSmall: kaitiTextStyle(
        baseTextTheme.titleSmall,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.textPrimary,
      ),
      bodyLarge: _sansTextStyle(
        fontSize: 15,
        height: 1.65,
        color: AppColors.textPrimary,
      ),
      bodyMedium: _sansTextStyle(
        fontSize: 14,
        height: 1.6,
        color: AppColors.textPrimary,
      ),
      bodySmall: _sansTextStyle(
        fontSize: 12,
        height: 1.5,
        letterSpacing: 0.15,
        color: AppColors.textSecondary,
      ),
      labelLarge: _sansTextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0.1,
        color: AppColors.textPrimary,
      ),
      labelMedium: _sansTextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.2,
        color: AppColors.textSecondary,
      ),
    );

    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
      borderSide: BorderSide(color: AppColors.border),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface.withValues(alpha: 0.94),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          borderSide: BorderSide(color: AppColors.brandStrong, width: 1.3),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          borderSide: BorderSide(color: AppColors.error, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface.withValues(alpha: 0.72),
          textStyle: textTheme.labelLarge,
          side: const BorderSide(color: AppColors.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandStrong,
          textStyle: textTheme.labelLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface.withValues(alpha: 0.96),
        indicatorColor: AppColors.brandSoft,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected) ? AppColors.brandStrong : AppColors.textSecondary;
          return textTheme.labelMedium?.copyWith(color: color);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected) ? AppColors.brandStrong : AppColors.textSecondary;
          return IconThemeData(color: color);
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface.withValues(alpha: 0.88),
        side: const BorderSide(color: AppColors.borderStrong),
        labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
        secondarySelectedColor: AppColors.brandSoft,
        selectedColor: AppColors.brandSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.brandSoft;
            }
            return AppColors.surface.withValues(alpha: 0.9);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.brandStrong;
            }
            return AppColors.textSecondary;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: AppColors.borderStrong)),
          textStyle: WidgetStateProperty.all(textTheme.labelLarge),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
