import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../features/campaign/domain/campaign.dart';

/// 案件カード。Instagram のフィード投稿に近い「店名ヘッダー + 本文 + 状態バッジ」構成。
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _StoreAvatar(storeName: campaign.storeName, dimmed: masked),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      campaign.storeName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (masked)
                    Icon(Icons.lock_outline,
                        size: 18, color: Colors.grey.shade500),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                campaign.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),

              // 報酬内容は条件を満たす場合のみ表示する
              if (masked)
                _MaskedLine(theme: theme)
              else
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.card_giftcard,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          campaign.rewardDescription,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _DeadlineBadge(applyEndAt: campaign.applyEndAt),
                  if (campaign.hasApplied)
                    const _StatusBadge(
                      icon: Icons.check_circle,
                      label: '応募済み',
                      color: AppTheme.successGreen,
                    ),
                ],
              ),

              if (masked) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  '応募条件を満たすと詳細が見られます',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 店名の頭文字を使った丸アイコン。SNS のアカウントアイコンの見え方に寄せる。
class _StoreAvatar extends StatelessWidget {
  const _StoreAvatar({required this.storeName, required this.dimmed});

  final String storeName;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: dimmed
          ? BoxDecoration(
              color: Colors.grey.shade300,
              shape: BoxShape.circle,
            )
          : const BoxDecoration(
              gradient: AppTheme.brandGradient,
              shape: BoxShape.circle,
            ),
      child: Text(
        storeName.isEmpty ? '?' : storeName.characters.first,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 応募締切バッジ。残り 3 日以内は色で緊急度を伝える。
class _DeadlineBadge extends StatelessWidget {
  const _DeadlineBadge({required this.applyEndAt});

  final DateTime applyEndAt;

  @override
  Widget build(BuildContext context) {
    final DateTime local = applyEndAt.toLocal();
    final int daysLeft = local.difference(DateTime.now()).inDays;
    final bool urgent = daysLeft >= 0 && daysLeft <= 3;
    return _StatusBadge(
      icon: Icons.schedule,
      label: urgent
          ? '締切間近 ${local.month}/${local.day}'
          : '締切 ${local.month}/${local.day}',
      color: urgent ? AppTheme.warningOrange : Colors.grey.shade600,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 伏せ字表現。実際の文字数を推測させないよう固定長にする。
class _MaskedLine extends StatelessWidget {
  const _MaskedLine({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
