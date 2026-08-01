import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/platform/platform_capability.dart';
import '../../../shared/widgets/install_prompt.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('案件詳細')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) =>
            const Center(child: Text('案件を取得できませんでした。')),
        data: (CampaignDetail campaign) => _Body(campaign: campaign),
      ),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(campaign.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(campaign.storeName, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          if (body == null) ...<Widget>[
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.lock_outline),
                        SizedBox(width: 8),
                        Text('この案件の応募条件を満たしていません'),
                      ],
                    ),
                    SizedBox(height: 8),
                    // 「どの条件が足りないか」は表示しない。
                    // 不足条件を出すと、自分や他者のインサイト値の推測材料になるため。
                    // 開示範囲の最終決定は OI-29。
                    Text('条件を満たすと、報酬内容や投稿条件を確認して応募できます。'),
                  ],
                ),
              ),
            ),
          ] else ...<Widget>[
            _Section(title: '報酬', child: Text(body.rewardDescription)),
            _Section(title: '投稿してほしい内容', child: Text(body.requiredContent)),
            _Section(
              title: '必須ハッシュタグ',
              child: Wrap(
                spacing: 8,
                children: body.hashtags
                    .map((String tag) => Chip(label: Text(tag)))
                    .toList(),
              ),
            ),
            _Section(
              title: '投稿期間',
              child: Text(
                '${_formatDate(body.postStartAt)} 〜 ${_formatDate(body.postEndAt)}',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _apply,
                child: const Text('応募する'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year}/${local.month}/${local.day}';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
