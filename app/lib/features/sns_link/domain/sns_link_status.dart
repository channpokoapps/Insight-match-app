import '../../search/domain/criteria.dart';

export '../../search/domain/criteria.dart' show SocialPlatform;

/// SNS 連携の状態。
///
/// **数値フィールドを定義しないこと。**
/// フォロワー数や平均リーチは本人にも返さない方針のため、型として存在させない
/// （AGENTS.md R-1 / R-3）。実数値は各 SNS の公式アプリで確認してもらう。
class SnsLinkStatus {
  const SnsLinkStatus({
    required this.platform,
    required this.state,
    required this.isReady,
    this.lastSyncedAt,
  });

  factory SnsLinkStatus.fromJson(Map<String, dynamic> json) => SnsLinkStatus(
        platform: SocialPlatform.values.firstWhere(
          (SocialPlatform p) => p.key == json['platform'],
          orElse: () => SocialPlatform.instagram,
        ),
        state: SnsLinkState.fromKey(json['status'] as String?),
        isReady: json['is_ready'] as bool? ?? false,
        lastSyncedAt: json['last_synced_at'] == null
            ? null
            : DateTime.parse(json['last_synced_at'] as String),
      );

  final SocialPlatform platform;
  final SnsLinkState state;

  /// 応募条件の判定に使えるデータが揃っているか。
  final bool isReady;

  /// 最終同期日時。インサイトに関わる表示には必ずこれを併記する（AGENTS.md 3章）。
  final DateTime? lastSyncedAt;

  bool get needsReauth => state == SnsLinkState.reauthRequired;
}

enum SnsLinkState {
  active('active', '連携中'),
  reauthRequired('reauth_required', '要再認可'),
  revoked('revoked', '連携解除');

  const SnsLinkState(this.key, this.label);

  final String key;
  final String label;

  static SnsLinkState fromKey(String? key) {
    for (final SnsLinkState state in SnsLinkState.values) {
      if (state.key == key) {
        return state;
      }
    }
    return SnsLinkState.revoked;
  }
}
