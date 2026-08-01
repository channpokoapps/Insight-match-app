import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/widgets/campaign_card.dart';
import '../data/campaign_repository.dart';
import '../domain/campaign.dart';

/// 案件一覧（投稿者向け）。
///
/// 応募条件を満たさない案件も一覧には出す（モザイク表示）。
/// これは「条件を満たせばもっと良い案件に応募できる」という動機づけのため（要件 6章）。
class CampaignListPage extends ConsumerWidget {
  const CampaignListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const CampaignListQuery query = CampaignListQuery();
    final AsyncValue<List<CampaignListItem>> campaigns =
        ref.watch(campaignListProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('案件をさがす')),
      body: campaigns.when(
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
                  onPressed: () => ref.invalidate(campaignListProvider(query)),
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
            onRefresh: () async => ref.invalidate(campaignListProvider(query)),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (BuildContext context, int index) {
                final CampaignListItem item = items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CampaignCard(
                    campaign: item,
                    onTap: () => context.push(AppRoutes.campaignDetail(item.id)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
