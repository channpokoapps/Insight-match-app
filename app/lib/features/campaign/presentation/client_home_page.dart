import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/platform/platform_capability.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/install_prompt.dart';
import '../../../shared/widgets/retry_notice.dart';
import '../data/client_campaign_repository.dart';
import '../domain/campaign_draft.dart';
import '../domain/client_campaign.dart';

/// PR依頼者のホーム画面。自分の案件一覧と作成導線。
///
/// 応募者の情報はここでは扱わない。応募状況は案件内連番（alias_no）のみを
/// 返すビュー経由で、応募管理画面（T-116 以降）が参照する。
class ClientHomePage extends ConsumerWidget {
  const ClientHomePage({super.key});

  Future<void> _onCreatePressed(BuildContext context, WidgetRef ref) async {
    if (!ref
        .read(platformCapabilityProvider)
        .isAvailable(AppFeature.campaignManagement)) {
      await showInstallPromptSheet(context, ref, AppFeature.campaignManagement);
      return;
    }
    await context.push(AppRoutes.campaignCreate);
  }

  Future<void> _onPublishPressed(
      BuildContext context, WidgetRef ref, ClientCampaign campaign) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('案件を公開しますか？'),
        content: Text('「${campaign.title}」の募集を開始します。'
            '公開すると条件に合う投稿者が応募できるようになります。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('公開する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(clientCampaignRepositoryProvider)
          .publishDraft(campaign.id);
      ref.invalidate(ownCampaignsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('案件を公開しました。')),
        );
      }
    } on AppFailure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ClientCampaign>> campaigns =
        ref.watch(ownCampaignsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('案件の管理')),
      bottomNavigationBar: const AppBottomNav(current: AppRoutes.clientHome),
      body: campaigns.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => RetryNotice(
          message: '案件一覧を取得できませんでした。',
          onRetry: () => ref.invalidate(ownCampaignsProvider),
        ),
        data: (List<ClientCampaign> items) => items.isEmpty
            ? const _EmptyState()
            : RefreshIndicator(
                onRefresh: () => ref.refresh(ownCampaignsProvider.future),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _CampaignCard(
                    campaign: items[index],
                    onPublish: (ClientCampaign campaign) =>
                        _onPublishPressed(context, ref, campaign),
                  ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
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
              '提供内容と募集条件を設定して案件を作成すると、\n条件に合う投稿者を募集できます。',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(height: 1.6, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign, required this.onPublish});

  final ClientCampaign campaign;
  final ValueChanged<ClientCampaign> onPublish;

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year}/${local.month}/${local.day}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> platformLabels = campaign.platforms
        .map((String p) => CampaignPlatform.fromWireName(p)?.label ?? p)
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: campaign.isDraft
                        ? Colors.grey.shade200
                        : theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    campaign.statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: campaign.isDraft
                          ? Colors.grey.shade700
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    platformLabels.join(' / '),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.grey.shade600),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              campaign.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '応募締切 ${_formatDate(campaign.applyEndAt)}'
              '${campaign.visitStartAt != null && campaign.visitEndAt != null ? ' ／ 訪問 ${_formatDate(campaign.visitStartAt!)}〜${_formatDate(campaign.visitEndAt!)}' : ''}'
              ' ／ 報告 ${_formatDate(campaign.postStartAt)}〜${_formatDate(campaign.postEndAt)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade700, height: 1.5),
            ),
            const SizedBox(height: 4),
            Text(
              '募集 ${campaign.quota}人 ／ 提供 ${campaign.rewardValueJpy}円相当',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade700),
            ),
            if (campaign.isDraft) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.publish_outlined, size: 18),
                  label: const Text('公開する'),
                  onPressed: () => onPublish(campaign),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
