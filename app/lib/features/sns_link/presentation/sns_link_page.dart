import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/platform/platform_capability.dart';
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
                    Text('連携について',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    const Text(
                      '・インサイトは案件の条件判定にのみ使われ、数値そのものは'
                      'あなたを含む誰にも表示されません。\n'
                      '・Instagram はビジネス／クリエイターアカウントで、'
                      'Facebook ページとの連携が必要です。\n'
                      '・データは1日1回自動で更新されます。',
                      style: TextStyle(fontSize: 13, height: 1.6),
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
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref.invalidate(mySnsLinkStatusProvider),
                      child: const Text('再読み込み'),
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
                      icon: Icons.camera_alt_outlined,
                      name: 'Instagram',
                      status: instagram,
                      starting: _starting,
                      onPressed: _startLink,
                    ),
                    const _ComingSoonTile(
                        icon: Icons.music_note_outlined, name: 'TikTok'),
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

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.icon,
    required this.name,
    required this.status,
    required this.starting,
    required this.onPressed,
  });

  final IconData icon;
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
          '連携中 ・ 最終同期 ${DateFormat('M月d日 HH:mm').format(s.lastSyncedAt!.toLocal())}';
    } else {
      subtitle = '連携中 ・ 初回データ取得中（数分かかることがあります）';
    }
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(name),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: starting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (s?.needsReauth ?? false)
                ? FilledButton.tonal(
                    onPressed: onPressed, child: const Text('再連携'))
                : linked
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : FilledButton(
                        onPressed: onPressed, child: const Text('連携する')),
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
      child: ListTile(
        enabled: false,
        leading: Icon(icon, size: 32),
        title: Text(name),
        subtitle: const Text('今後対応予定', style: TextStyle(fontSize: 12)),
      ),
    );
  }
}
