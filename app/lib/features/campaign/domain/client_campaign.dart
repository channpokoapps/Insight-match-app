import '../../search/domain/criteria.dart';
import 'campaign_draft.dart';

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

  /// 編集・取り下げができる状態か。完了・中止後は変更させない。
  bool get isEditable => const <String>{
        'draft',
        'recruiting',
        'screening',
        'relaxation_proposed',
      }.contains(status);

  /// 状態の表示名。想定外の値はそのまま出す（隠すより調査しやすい）。
  String get statusLabel => statusLabelOf(status);

  static String statusLabelOf(String status) => switch (status) {
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

/// 編集画面で扱う案件 1 件の全項目。
///
/// 応募条件（criteria）は PR依頼者自身が設定したものなので、
/// 所有者に返してよい。**投稿者向けの型には決して持たせない**（AGENTS.md §3）。
class EditableCampaign {
  const EditableCampaign({
    required this.id,
    required this.status,
    required this.draft,
    required this.criteria,
    required this.images,
    required this.applicantCount,
  });

  factory EditableCampaign.fromRows({
    required Map<String, dynamic> row,
    required List<Map<String, dynamic>> tags,
    required List<Map<String, dynamic>> images,
    required int applicantCount,
  }) {
    final dynamic rawCriteria = row['criteria'];
    return EditableCampaign(
      id: row['id'] as String,
      status: row['status'] as String,
      draft: CampaignDraft(
        title: row['title'] as String,
        storeName: row['store_name_snapshot'] as String,
        platforms: (row['platforms'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => CampaignPlatform.fromWireName(e as String))
            .whereType<CampaignPlatform>()
            .toSet(),
        rewardDescription: row['reward_description'] as String,
        rewardValueJpy: row['reward_value_jpy'] as int?,
        quota: row['quota'] as int?,
        applyEndDate: DateTime.parse(row['apply_end_at'] as String).toLocal(),
        visitStartDate: _localDateOr(row['visit_start_at'], row['post_start_at']),
        visitEndDate: _localDateOr(row['visit_end_at'], row['post_end_at']),
        postStartDate: DateTime.parse(row['post_start_at'] as String).toLocal(),
        postEndDate: DateTime.parse(row['post_end_at'] as String).toLocal(),
        requiredContent: row['required_content'] as String,
        genreId: row['genre_id'] as int?,
        // 広告表記タグはサーバーが付けるものなので編集対象に含めない。
        hashtags: tags
            .where((Map<String, dynamic> t) => t['is_mandatory'] != true)
            .map((Map<String, dynamic> t) => t['tag'] as String)
            .toList(),
        prefectureId: row['prefecture_id'] as int?,
        cityId: row['city_id'] as int?,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
        nearestStationId: row['nearest_station_id'] as int?,
      ),
      criteria: rawCriteria == null
          ? null
          : Criteria.fromJson(rawCriteria as Map<String, dynamic>),
      images: images
          .map((Map<String, dynamic> i) => i['storage_path'] as String)
          .toList(),
      applicantCount: applicantCount,
    );
  }

  final String id;
  final String status;
  final CampaignDraft draft;
  final Criteria? criteria;
  final List<String> images;

  /// 応募件数。1 件以上なら募集条件・人数・期間・投稿対象を編集できない
  /// （FR-CMP-13。判定の担保はサーバー側のトリガー）。
  final int applicantCount;

  bool get isLocked => applicantCount > 0;

  static DateTime _localDateOr(dynamic value, dynamic fallback) =>
      DateTime.parse((value ?? fallback) as String).toLocal();
}
