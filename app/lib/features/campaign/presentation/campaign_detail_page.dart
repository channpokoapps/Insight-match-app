import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/platform/platform_capability.dart';
import '../../../shared/widgets/install_prompt.dart';
import '../../../shared/widgets/retry_notice.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/campaign_repository.dart';
import '../domain/campaign.dart';

final FutureProviderFamily<CampaignDetail, String> campaignDetailProvider =
    FutureProvider.family<CampaignDetail, String>(
  (Ref ref, String campaignId) =>
      ref.watch(campaignRepositoryProvider).getDetail(campaignId),
);

/// 案件詳細（投稿者向け）。
///
/// 条件を満たさない場合、`detail` が null で返る。
/// このとき詳細情報は端末に届いていないため、表示側で復元することはできない。
class CampaignDetailPage extends ConsumerWidget {
  const CampaignDetailPage({required this.campaignId, super.key});

  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CampaignDetail> detail =
        ref.watch(campaignDetailProvider(campaignId));

    return detail.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('案件詳細')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, StackTrace _) => Scaffold(
        appBar: AppBar(title: const Text('案件詳細')),
        body: RetryNotice(
          message: '案件を取得できませんでした。',
          onRetry: () => ref.invalidate(campaignDetailProvider(campaignId)),
        ),
      ),
      data: (CampaignDetail campaign) => _Body(campaign: campaign),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.campaign});

  final CampaignDetail campaign;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _submitting = false;

  Future<void> _apply() async {
    // Web お試し版ではサーバーに投げる前にインストール導線を出す。
    // 権限の担保はあくまで RLS / RPC 側（AGENTS.md R-8）。
    if (!ref
        .read(platformCapabilityProvider)
        .isAvailable(AppFeature.campaignApplication)) {
      await showInstallPromptSheet(
          context, ref, AppFeature.campaignApplication);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(campaignRepositoryProvider).apply(widget.campaign.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('応募しました。')),
      );
    } on AppFailure catch (failure) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message)),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final CampaignDetail campaign = widget.campaign;
    final CampaignDetailBody? body = campaign.detail;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('案件詳細')),
      // 応募ボタンはスクロール位置に関係なく届く固定フッターに置く
      // （チャットアプリの送信ボタンと同じ到達性を持たせる）。
      bottomNavigationBar: body == null
          ? null
          : Container(
              color: Colors.white,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: SubmitButton(
                    label: 'この案件に応募する',
                    submitting: _submitting,
                    onPressed: _apply,
                  ),
                ),
              ),
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              campaign.title,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(Icons.storefront_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    campaign.storeName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (body == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lock_outline,
                            size: 28, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'この案件の応募条件を満たしていません',
                        style: theme.textTheme.titleSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      // 「どの条件が足りないか」は表示しない。
                      // 不足条件を出すと、自分や他者のインサイト値の推測材料になるため。
                      // 開示範囲の最終決定は OI-29。
                      Text(
                        '条件を満たすと、報酬内容や投稿条件を確認して応募できます。',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...<Widget>[
              _DetailSectionCard(
                icon: Icons.card_giftcard,
                title: '報酬',
                child: Text(body.rewardDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
              ),
              _DetailSectionCard(
                icon: Icons.edit_note,
                title: '投稿してほしい内容',
                child: Text(body.requiredContent,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
              ),
              _DetailSectionCard(
                icon: Icons.tag,
                title: '必須ハッシュタグ',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: body.hashtags
                      .map(
                        (String tag) => Chip(
                          label: Text(
                            tag.startsWith('#') ? tag : '#$tag',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: theme.colorScheme.primary
                              .withValues(alpha: 0.08),
                          side: BorderSide.none,
                        ),
                      )
                      .toList(),
                ),
              ),
              _DetailSectionCard(
                icon: Icons.event_available,
                title: '投稿期間',
                child: Text(
                  '${_formatDate(body.postStartAt)} 〜 ${_formatDate(body.postEndAt)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year}/${local.month}/${local.day}';
  }
}

/// アイコン + 見出し付きのセクションカード。情報のまとまりを視覚的に区切る。
/// (settings_page.dart の `_SectionCard` はメニューのグルーピング用で別物)
class _DetailSectionCard extends StatelessWidget {
  const _DetailSectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
