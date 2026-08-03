import 'package:flutter/material.dart';

/// 送信中インジケータ付きのボタン。
///
/// 「送信中は無効化して CircularProgressIndicator、通常時はラベル」という
/// 各フォーム画面でコピペされていた定型を一箇所に集約したもの。
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    required this.label,
    required this.submitting,
    required this.onPressed,
    this.enabled = true,
    super.key,
  });

  /// ボタンの文言。
  final String label;

  /// true の間はボタンを無効化してスピナーを表示する。
  final bool submitting;

  /// 押されたときの処理。
  final VoidCallback onPressed;

  /// false の間はボタンを無効化する(例: 同意チェックが未チェック)。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: submitting || !enabled ? null : onPressed,
      child: submitting
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
