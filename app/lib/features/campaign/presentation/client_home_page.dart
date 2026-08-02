import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_capability.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
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
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('案件の管理')),
      bottomNavigationBar: const AppBottomNav(current: AppRoutes.clientHome),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.campaign_outlined,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'まだ案件がありません',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'インサイト条件を設定して案件を作成すると、\n条件に合う投稿者を募集できます。',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(height: 1.6, color: Colors.grey.shade600),
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
