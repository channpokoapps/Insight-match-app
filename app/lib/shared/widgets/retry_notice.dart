import 'package:flutter/material.dart';

/// 通信失敗時の「再読み込み」案内。
///
/// wifi_off アイコン + メッセージ + 再試行ボタンの定型をまとめる。
/// 各画面でコピペされていた表示を一箇所に集約したもの。
class RetryNotice extends StatelessWidget {
  const RetryNotice({
    required this.message,
    required this.onRetry,
    this.buttonLabel = '再読み込み',
    super.key,
  });

  /// 利用者向けの状況説明(例: '案件を取得できませんでした。')。
  final String message;

  /// 再試行ボタンが押されたときの処理。
  final VoidCallback onRetry;

  /// ボタンの文言。既定は「再読み込み」。
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.wifi_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              onPressed: onRetry,
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
