/// ネイティブアプリへのインストール導線を提供するファイル。
///
/// Web お試し版からの主要な転換点であり、次の 2 つのボタンをまとめる。
/// - Android: ストア URL が設定済みなら開き、未公開の間は「準備中」を案内する。
///   どちらの場合もイベントを記録し、公開前から導線の効果を計測できるようにする。
/// - iOS: 未提供の間は「Coming Soon」ダイアログを表示し、タップ数を
///   `ios_interest` イベントとして記録する（iOS 版開発の需要見積もりに使う）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics/analytics_service.dart';
import '../../core/config/app_config.dart';
import '../../core/platform/platform_capability.dart';

/// Android / iOS アプリへの誘導ボタンの組。
class AppInstallButtons extends ConsumerWidget {
  /// ウィジェットを生成する。
  ///
  /// [launchUrlImpl] テスト用の URL 起動実装。省略時は url_launcher を使う。
  const AppInstallButtons({
    Future<bool> Function(Uri url)? launchUrlImpl,
    super.key,
  }) : _launchUrlImpl = launchUrlImpl ?? launchUrl;

  final Future<bool> Function(Uri url) _launchUrlImpl;

  Future<void> _onAndroidPressed(BuildContext context, WidgetRef ref) async {
    final AppConfig config = ref.read(appConfigProvider);
    // 公開前からタップ数を計測し、導線の効果とストア公開の優先度判断に使う。
    await ref
        .read(analyticsServiceProvider)
        .logEvent(EVENT_INSTALL_CTA_ANDROID);
    if (config.androidStoreUrl.isEmpty) {
      if (!context.mounted) {
        return;
      }
      await _showComingSoonDialog(
        context,
        title: 'Android アプリは準備中です',
        message: 'ストア公開の準備を進めています。公開までしばらくお待ちください。',
      );
      return;
    }
    await _launchUrlImpl(Uri.parse(config.androidStoreUrl));
  }

  Future<void> _onIosPressed(BuildContext context, WidgetRef ref) async {
    final AppConfig config = ref.read(appConfigProvider);
    if (config.isIosAvailable && config.iosStoreUrl.isNotEmpty) {
      await _launchUrlImpl(Uri.parse(config.iosStoreUrl));
      return;
    }
    // タップ数が iOS 版開発の需要見積もりになる。
    await ref.read(analyticsServiceProvider).logEvent(EVENT_IOS_INTEREST);
    if (!context.mounted) {
      return;
    }
    await _showComingSoonDialog(
      context,
      title: 'iOS 版は Coming Soon',
      message: 'iOS 版は現在開発を検討中です。ご要望として記録しました。',
    );
  }

  Future<void> _showComingSoonDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          icon: const Icon(Icons.android),
          label: const Text('Android アプリを入手'),
          onPressed: () => _onAndroidPressed(context, ref),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.phone_iphone),
          label: Text(
            config.isIosAvailable ? 'iOS アプリを入手' : 'iOS 版 (Coming Soon)',
          ),
          onPressed: () => _onIosPressed(context, ref),
        ),
      ],
    );
  }
}

/// Web 版で無効な機能がタップされたときのインストール誘導ボトムシート。
///
/// [feature] タップされた機能。どの機能への欲求が強いかを
/// `web_feature_blocked` イベントとして計測する。
Future<void> showInstallPromptSheet(
  BuildContext context,
  WidgetRef ref,
  AppFeature feature,
) async {
  final PlatformCapability capability = ref.read(platformCapabilityProvider);
  await ref.read(analyticsServiceProvider).logEvent(
    EVENT_WEB_FEATURE_BLOCKED,
    parameters: <String, Object>{'feature': feature.name},
  );
  if (!context.mounted) {
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Icon(Icons.install_mobile, size: 48),
            const SizedBox(height: 12),
            Text(
              capability.unavailableReason(feature) ??
                  capability.webTrialNotice(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            const AppInstallButtons(),
          ],
        ),
      ),
    ),
  );
}
