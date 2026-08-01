import 'package:flutter/material.dart';

import '../../features/campaign/domain/campaign.dart';

/// 案件カード。
///
/// 応募条件を満たさない案件は、報酬内容・所在地・必須投稿内容を伏せて表示する。
/// **伏せる情報はサーバから送られてこない**ため、ここで隠しているのは
/// 「そもそも存在しない値」であり、ウィジェットを差し替えても中身は見えない。
class CampaignCard extends StatelessWidget {
  const CampaignCard({
    required this.campaign,
    required this.onTap,
    super.key,
  });

  final CampaignListItem campaign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool masked = !campaign.isEligible;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      campaign.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (masked)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.lock_outline, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(campaign.storeName, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),

              // 報酬内容は条件を満たす場合のみ表示する
              if (masked)
                _MaskedLine(theme: theme)
              else
                Text(campaign.rewardDescription,
                    style: theme.textTheme.bodyMedium),

              const SizedBox(height: 8),
              Text(
                '応募締切 ${_formatDate(campaign.applyEndAt)}',
                style: theme.textTheme.bodySmall,
              ),

              if (masked) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'この案件の応募条件を満たしていません',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              if (campaign.hasApplied) ...<Widget>[
                const SizedBox(height: 8),
                const Chip(
                  label: Text('応募済み'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year}/${local.month}/${local.day}';
  }
}

/// 伏せ字表現。実際の文字数を推測させないよう固定長にする。
class _MaskedLine extends StatelessWidget {
  const _MaskedLine({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
