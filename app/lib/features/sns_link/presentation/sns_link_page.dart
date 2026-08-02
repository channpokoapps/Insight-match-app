import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/platform/platform_capability.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/install_prompt.dart';
import '../data/sns_link_repository.dart';
import '../domain/sns_link_status.dart';

/// SNS 連携画面。
///
/// 連携の状態と最終同期日時のみを表示する。
/// **フォロワー数などの数値はこの画面にも出さない**（AGENTS.md R-1 / R-3。
/// 実数値は各 SNS の公式アプリで確認してもらう）。
class SnsLinkPage extends ConsumerStatefulWidget {
  const SnsLinkPage({super.key});

  @override
  ConsumerState<SnsLinkPage> createState() => _SnsLinkPageState();
}

class _SnsLinkPageState extends ConsumerState<SnsLinkPage>
    with WidgetsBindingObserver {
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 外部ブラウザでの認可から戻ってきたら状態を取り直す。
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(mySnsLinkStatusProvider);
    }
  }

  Future<void> _startLink() async {
    if (!ref.read(platformCapabilityProvider).isAvailable(AppFeature.snsLink)) {
      await showInstallPromptSheet(context, ref, AppFeature.snsLink);
      return;
    }
    setState(() => _starting = true);
    try {
      final Uri url =
          await ref.read(snsLinkRepositoryProvider).startInstagramLink();
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } on AppFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SnsLinkStatus>> statuses =
        ref.watch(mySnsLinkStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('SNS 連携')),
      bottomNavigationBar: const AppBottomNav(current: AppRoutes.snsLink),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mySnsLinkStatusProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.verified_user_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '連携について',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '・インサイトは案件の条件判定にのみ使われ、数値そのものは'
                      'あなたを含む誰にも表示されません。\n'
                      '・Instagram はビジネス／クリエイターアカウントで、'
                      'Facebook ページとの連携が必要です。\n'
                      '・データは1日1回自動で更新されます。',
                      style: TextStyle(fontSize: 13, height: 1.7),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            statuses.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object e, StackTrace _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    const Text('連携状態を取得できませんでした。'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => ref.invalidate(mySnsLinkStatusProvider),
                      label: const Text('再読み込み'),
                    ),
                  ],
                ),
              ),
              data: (List<SnsLinkStatus> list) {
                SnsLinkStatus? instagram;
                for (final SnsLinkStatus s in list) {
                  if (s.platform == SocialPlatform.instagram) {
                    instagram = s;
                    break;
                  }
                }
                return Column(
                  children: <Widget>[
                    _PlatformTile(
                      avatar: const _PlatformAvatar(
                        icon: Icons.camera_alt_outlined,
                        gradient: AppTheme.brandGradient,
                      ),
                      name: 'Instagram',
                      status: instagram,
                      starting: _starting,
                      onPressed: _startLink,
                    ),
                    const SizedBox(height: 8),
                    const _ComingSoonTile(
                        icon: Icons.music_note_outlined, name: 'TikTok'),
                    const SizedBox(height: 8),
                    const _ComingSoonTile(
                        icon: Icons.play_circle_outline, name: 'YouTube'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// SNS アイコンの丸型アバター。
class _PlatformAvatar extends StatelessWidget {
  const _PlatformAvatar({
    required this.icon,
    this.gradient,
    this.color,
  });

  final IconData icon;
  final Gradient? gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: gradient,
        color: color,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.avatar,
    required this.name,
    required this.status,
    required this.starting,
    required this.onPressed,
  });

  final Widget avatar;
  final String name;
  final SnsLinkStatus? status;
  final bool starting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final SnsLinkStatus? s = status;
    final bool linked = s != null && s.state == SnsLinkState.active;
    final String subtitle;
    if (s == null || s.state == SnsLinkState.revoked) {
      subtitle = '未連携';
    } else if (s.needsReauth) {
      subtitle = '再認可が必要です。もう一度連携してください。';
    } else if (s.lastSyncedAt != null) {
      subtitle =
          '最終同期 ${DateFormat('M月d日 HH:mm').format(s.lastSyncedAt!.toLocal())}';
    } else {
      subtitle = '初回データ取得中（数分かかることがあります）';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      if (linked && !s.needsReauth) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.successGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            '連携中',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.successGreen,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (starting)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (s?.needsReauth ?? false)
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: onPressed,
                child: const Text('再連携'),
              )
            else if (linked)
              const Icon(Icons.check_circle, color: AppTheme.successGreen)
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                onPressed: onPressed,
                child: const Text('連携する'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile({required this.icon, required this.name});

  final IconData icon;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            _PlatformAvatar(icon: icon, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '今後対応予定',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
