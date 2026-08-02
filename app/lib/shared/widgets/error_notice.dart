import 'package:flutter/material.dart';

/// フォーム下部に出すエラー表示。
///
/// 素のテキストだと見落とされやすいため、アイコン付きの
/// 角丸コンテナで「何が起きたか」を一目で伝える。
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 20, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.error, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
