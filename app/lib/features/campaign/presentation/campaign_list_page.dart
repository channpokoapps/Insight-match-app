import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/platform_capability.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/campaign_card.dart';
import '../data/campaign_repository.dart';
import '../domain/campaign.dart';

/// 案件一覧（投稿者向け）。
///
/// 応募条件を満たさない案件も一覧には出す（モザイク表示）。
/// これは「条件を満たせばもっと良い案件に応募できる」という動機づけのため（要件 6章）。
class CampaignListPage extends ConsumerStatefulWidget {
  const CampaignListPage({super.key});

  @override
  ConsumerState<CampaignListPage> createState() => _CampaignListPageState();
}

class _CampaignListPageState extends ConsumerState<CampaignListPage> {
  /// Web お試し版の案内バナーを表示するか。閉じたらセッション中は再表示しない。
  late bool _showTrialBanner = ref.read(platformCapabilityProvider).isWeb;

  @override
  Widget build(BuildContext context) {
    const CampaignListQuery query = CampaignListQuery();
    final AsyncValue<List<CampaignListItem>> campaigns =
        ref.watch(campaignListProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('案件をさがす'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_showTrialBanner)
            MaterialBanner(
              content: Text(
                ref.read(platformCapabilityProvider).webTrialNotice(),
              ),
              leading: const Icon(Icons.info_outline),
              actions: <Widget>[
                TextButton(
                  onPressed: () => setState(() => _showTrialBanner = false),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          Expanded(
            child: campaigns.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('案件を取得できませんでした。'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(campaignListProvider(query)),
                        child: const Text('再読み込み'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (List<CampaignListItem> items) {
                if (items.isEmpty) {
                  return const Center(child: Text('現在募集中の案件はありません。'));
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(campaignListProvider(query)),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    itemBuilder: (BuildContext context, int index) {
                      final CampaignListItem item = items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: CampaignCard(
                          campaign: item,
                          onTap: () =>
                              context.push(AppRoutes.campaignDetail(item.id)),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
