import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/platform_capability.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/campaign_card.dart';
import '../../sns_link/data/sns_link_repository.dart';
import '../../sns_link/domain/sns_link_status.dart';
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

  /// SNS 未連携の案内バナーを表示するか（Android のみ）。
  bool _showSnsBanner = true;

  /// Instagram が未連携（または要再認可）かどうか。取得前は false。
  bool _needsSnsLink() {
    if (ref.read(platformCapabilityProvider).isWeb) {
      return false;
    }
    final List<SnsLinkStatus>? statuses =
        ref.watch(mySnsLinkStatusProvider).valueOrNull;
    if (statuses == null) {
      return false;
    }
    for (final SnsLinkStatus s in statuses) {
      if (s.platform == SocialPlatform.instagram &&
          s.state == SnsLinkState.active) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    const CampaignListQuery query = CampaignListQuery();
    final AsyncValue<List<CampaignListItem>> campaigns =
        ref.watch(campaignListProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('案件をさがす')),
      bottomNavigationBar: const AppBottomNav(current: AppRoutes.campaignList),
      body: campaigns.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.wifi_off, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text('案件を取得できませんでした。'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(campaignListProvider(query)),
                  label: const Text('再読み込み'),
                ),
              ],
            ),
          ),
        ),
        data: (List<CampaignListItem> items) {
          final List<Widget> headers = <Widget>[
            if (_showTrialBanner)
              _NoticeCard(
                icon: Icons.info_outline,
                text: ref.read(platformCapabilityProvider).webTrialNotice(),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => setState(() => _showTrialBanner = false),
                    child: const Text('閉じる'),
                  ),
                ],
              )
            else if (_showSnsBanner && _needsSnsLink())
              _NoticeCard(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_outlined,
                      color: Colors.white, size: 22),
                ),
                text: 'Instagram を連携すると、条件に合う案件へ応募できるようになります。',
                actions: <Widget>[
                  TextButton(
                    onPressed: () => setState(() => _showSnsBanner = false),
                    child: const Text('あとで'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    onPressed: () => context.go(AppRoutes.snsLink),
                    child: const Text('連携する'),
                  ),
                ],
              ),
          ];

          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                ...headers,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80),
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.storefront_outlined,
                          size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        '現在募集中の案件はありません',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '新しい案件が公開されるとここに表示されます。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(campaignListProvider(query)),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: headers.length + items.length,
              itemBuilder: (BuildContext context, int index) {
                if (index < headers.length) {
                  return headers[index];
                }
                final CampaignListItem item = items[index - headers.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
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
    );
  }
}

/// フィード先頭に差し込むお知らせカード。
/// MaterialBanner よりも SNS の「おすすめ」カードに近い見た目にする。
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.text,
    required this.actions,
    this.icon,
    this.leading,
  });

  final String text;
  final List<Widget> actions;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  leading ??
                      Icon(icon, size: 24, color: Colors.grey.shade600),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  for (int i = 0; i < actions.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
