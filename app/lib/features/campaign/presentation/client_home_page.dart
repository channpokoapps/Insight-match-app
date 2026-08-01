import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/platform_capability.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/install_prompt.dart';

/// PR依頼者のホーム画面。
///
/// 案件の作成・管理（Phase 5, T-110〜116）が実装されるまでの受け皿。
/// Web 版では案件作成がインストール導線になることをここで体験させる。
class ClientHomePage extends ConsumerWidget {
  const ClientHomePage({super.key});

  Future<void> _onCreatePressed(BuildContext context, WidgetRef ref) async {
    if (!ref
        .read(platformCapabilityProvider)
        .isAvailable(AppFeature.campaignManagement)) {
      await showInstallPromptSheet(context, ref, AppFeature.campaignManagement);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('案件の作成機能は現在開発中です。')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('案件の管理'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.campaign_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'まだ案件がありません',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'インサイト条件を設定して案件を作成すると、\n条件に合う投稿者を募集できます。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('案件を作成'),
        onPressed: () => _onCreatePressed(context, ref),
      ),
    );
  }
}
