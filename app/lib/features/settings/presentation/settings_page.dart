import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/platform/platform_capability.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/install_prompt.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/profile_repository.dart';
import '../../auth/domain/app_role.dart';

/// 設定画面。
///
/// アカウント情報・規約リンク・ログアウトに加え、Web 版では
/// アプリのインストール導線を常設する（お試し版からの転換点）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ページは準備中です。')),
      );
      return;
    }
    await launchUrl(Uri.parse(url));
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  Future<void> _showWithdrawDialog(
      BuildContext context, AppConfig config) async {
    // 退会の完全削除フローはレポートスナップショット設計（OI-36）確定後に実装する。
    // それまでは問い合わせ窓口での手動対応とする。
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('退会のお手続き'),
        content: Text(
          '現在、退会はお問い合わせでの受付となっています。\n'
          '${config.supportEmail} までご連絡ください。',
        ),
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
    final PlatformCapability capability = ref.watch(platformCapabilityProvider);
    final UserProfile? profile = ref.watch(myProfileProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: <Widget>[
          if (profile != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(profile.role.label),
              subtitle: Text('アカウント状態: ${profile.status.label}'),
            ),
          if (profile?.role == AppRole.creator)
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('SNS 連携'),
              subtitle: const Text('Instagram アカウントの連携・状態確認'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.snsLink),
            ),
          if (capability.isWeb) ...<Widget>[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'アプリをダウンロード',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    capability.webTrialNotice(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  const AppInstallButtons(),
                ],
              ),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('利用規約'),
            onTap: () => _openUrl(context, config.termsUrl),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('プライバシーポリシー'),
            onTap: () => _openUrl(context, config.privacyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('お問い合わせ'),
            subtitle: Text(config.supportEmail),
            onTap: () => _openUrl(context, 'mailto:${config.supportEmail}'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('ログアウト'),
            onTap: () => _confirmSignOut(context, ref),
          ),
          ListTile(
            leading: Icon(
              Icons.person_off_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '退会',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => _showWithdrawDialog(context, config),
          ),
        ],
      ),
    );
  }
}
