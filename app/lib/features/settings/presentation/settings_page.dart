import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/platform/platform_capability.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/install_prompt.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/profile_repository.dart';
import '../../auth/domain/app_role.dart';

/// マイページ（設定）画面。
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
      appBar: AppBar(title: const Text('マイページ')),
      bottomNavigationBar: const AppBottomNav(current: AppRoutes.settings),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (profile != null) ...<Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        profile.role == AppRole.client
                            ? Icons.storefront_outlined
                            : Icons.photo_camera_outlined,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            profile.role.label,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'アカウント状態: ${profile.status.label}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (profile?.role == AppRole.client) ...<Widget>[
            _SectionCard(
              children: <Widget>[
                _MenuTile(
                  icon: Icons.storefront_outlined,
                  title: '店舗情報',
                  subtitle: '店名・所在地・ジャンル・紹介文の変更',
                  onTap: () => context.push(AppRoutes.storeProfile),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (profile?.role == AppRole.creator) ...<Widget>[
            _SectionCard(
              children: <Widget>[
                _MenuTile(
                  icon: Icons.link,
                  title: 'SNS 連携',
                  subtitle: 'Instagram アカウントの連携・状態確認',
                  onTap: () => context.go(AppRoutes.snsLink),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (capability.isWeb) ...<Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'アプリをダウンロード',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      capability.webTrialNotice(),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    const AppInstallButtons(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SectionCard(
            children: <Widget>[
              _MenuTile(
                icon: Icons.description_outlined,
                title: '利用規約',
                onTap: () => _openUrl(context, config.termsUrl),
              ),
              _MenuTile(
                icon: Icons.privacy_tip_outlined,
                title: 'プライバシーポリシー',
                onTap: () => _openUrl(context, config.privacyUrl),
              ),
              _MenuTile(
                icon: Icons.mail_outline,
                title: 'お問い合わせ',
                subtitle: config.supportEmail,
                onTap: () => _openUrl(context, 'mailto:${config.supportEmail}'),
              ),
              // 駅データは CC BY 4.0。クレジット表示が利用条件なので必ず残すこと。
              _MenuTile(
                icon: Icons.dataset_outlined,
                title: 'データ出典',
                onTap: () => context.push(AppRoutes.dataSources),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            children: <Widget>[
              _MenuTile(
                icon: Icons.logout,
                title: 'ログアウト',
                showChevron: false,
                onTap: () => _confirmSignOut(context, ref),
              ),
              _MenuTile(
                icon: Icons.person_off_outlined,
                title: '退会',
                color: Theme.of(context).colorScheme.error,
                showChevron: false,
                onTap: () => _showWithdrawDialog(context, config),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// メニュー項目をまとめる角丸カード。LINE の設定画面のグルーピングに寄せる。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, indent: 56, color: Colors.grey.shade100),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.grey.shade700),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color ?? Colors.black87,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
      trailing: showChevron
          ? const Icon(Icons.chevron_right, color: Colors.grey)
          : null,
      onTap: onTap,
    );
  }
}
