import 'package:flutter/material.dart';

/// アプリ全体のテーマ定義。
///
/// 主要ターゲットが Instagram / LINE を日常的に使う層のため、
/// 両アプリの操作感に寄せる:
/// - 丸み(ピル型ボタン・角丸カード)と白基調 + 薄グレー背景
/// - 指で押しやすい高さ 52px 以上の主要ボタン
/// - 枠線ではなく塗りつぶしの入力欄
/// - アクセントは Instagram 系マゼンタ、連携済みの成功表現は LINE 系グリーン
class AppTheme {
  const AppTheme._();

  /// ブランドのメインカラー(Instagram 系マゼンタ)。
  static const Color brandPrimary = Color(0xFFDD2A7B);

  /// 連携済み・成功状態に使うグリーン(LINE 系)。
  static const Color successGreen = Color(0xFF06C755);

  /// ロゴマークや装飾に使うブランドグラデーション。
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFFF58529),
      Color(0xFFDD2A7B),
      Color(0xFF8134AF),
    ],
  );

  /// 締切間近など注意を促す色。
  static const Color warningOrange = Color(0xFFF58529);

  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: brandPrimary,
      surface: Colors.white,
    );
    final RoundedRectangleBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: cardShape.copyWith(
          side: BorderSide(color: Colors.grey.shade200),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
          side: BorderSide(color: Colors.grey.shade300),
          foregroundColor: scheme.onSurface,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF2F3F5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      chipTheme: const ChipThemeData(
        shape: StadiumBorder(side: BorderSide(color: Colors.transparent)),
        labelStyle: TextStyle(fontSize: 12),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : Colors.grey.shade600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : Colors.grey.shade600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }
}

/// ブランドグラデーションの丸型ロゴマーク。
///
/// ログイン・スプラッシュなどで共通に使い、アプリの第一印象を揃える。
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 72, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: AppTheme.brandGradient,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.auto_awesome,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}
