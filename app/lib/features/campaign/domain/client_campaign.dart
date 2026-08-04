/// PR依頼者が自分の案件一覧で見る 1 件分。
///
/// 自分の案件のみ（RLS `campaigns_owner_all`）。応募者の情報は含めない。
/// 応募状況は `v_applications_for_client`（alias_no のみ）を別途参照する。
class ClientCampaign {
  const ClientCampaign({
    required this.id,
    required this.status,
    required this.title,
    required this.rewardValueJpy,
    required this.quota,
    required this.platforms,
    required this.applyEndAt,
    required this.postStartAt,
    required this.postEndAt,
    required this.createdAt,
    this.visitStartAt,
    this.visitEndAt,
    this.publishedAt,
  });

  factory ClientCampaign.fromJson(Map<String, dynamic> json) => ClientCampaign(
        id: json['id'] as String,
        status: json['status'] as String,
        title: json['title'] as String,
        rewardValueJpy: json['reward_value_jpy'] as int,
        quota: json['quota'] as int,
        platforms: (json['platforms'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e as String)
            .toList(),
        applyEndAt: DateTime.parse(json['apply_end_at'] as String),
        postStartAt: DateTime.parse(json['post_start_at'] as String),
        postEndAt: DateTime.parse(json['post_end_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        visitStartAt: json['visit_start_at'] == null
            ? null
            : DateTime.parse(json['visit_start_at'] as String),
        visitEndAt: json['visit_end_at'] == null
            ? null
            : DateTime.parse(json['visit_end_at'] as String),
        publishedAt: json['published_at'] == null
            ? null
            : DateTime.parse(json['published_at'] as String),
      );

  final String id;
  final String status;
  final String title;
  final int rewardValueJpy;
  final int quota;
  final List<String> platforms;
  final DateTime applyEndAt;
  final DateTime postStartAt;
  final DateTime postEndAt;
  final DateTime createdAt;
  final DateTime? visitStartAt;
  final DateTime? visitEndAt;
  final DateTime? publishedAt;

  bool get isDraft => status == 'draft';

  /// 状態の表示名。想定外の値はそのまま出す（隠すより調査しやすい）。
  String get statusLabel => switch (status) {
        'draft' => '下書き',
        'recruiting' => '募集中',
        'screening' => '選考中',
        'relaxation_proposed' => '条件緩和の提案中',
        'in_progress' => '進行中',
        'posting_closed' => '投稿締切',
        'completed' => '完了',
        'cancelled' => '中止',
        'suspended' => '停止中',
        _ => status,
      };
}
