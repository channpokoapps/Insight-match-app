/// 案件作成の入力内容と検証（FR-CMP-01〜03 / 06〜10 / 12）。
///
/// 検証は DB の check 制約（0015_campaign_creation.sql）と同じ規則を
/// クライアント側でも行い、送信前に日本語のエラーメッセージを返す。
/// ただし最終的な担保は DB 側の制約と RLS（AGENTS.md R-8）。
library;

import '../../search/domain/criteria.dart';

/// 案件の投稿対象 SNS。値域は `social_links.platform` と揃える。
enum CampaignPlatform {
  instagram('instagram', 'Instagram'),
  tiktok('tiktok', 'TikTok'),
  youtube('youtube', 'YouTube');

  const CampaignPlatform(this.wireName, this.label);

  /// DB に保存する値。
  final String wireName;

  /// 画面表示名。
  final String label;

  static CampaignPlatform? fromWireName(String value) {
    for (final CampaignPlatform p in CampaignPlatform.values) {
      if (p.wireName == value) {
        return p;
      }
    }
    return null;
  }
}

/// ステマ規制対応の広告表記タグ。サーバー側で自動付与され削除できない（OI-04）。
const String adDisclosureTag = '#PR';

/// 案件作成フォームの入力内容。
///
/// 期間は日付単位で受け取り、送信時に
/// 「締切・終了 = その日の 23:59:59」「開始 = その日の 0:00」へ展開する。
/// 順序の規則は「応募締切 → 訪問期間 → 報告期間」の 3 段階:
/// 応募締切 < 訪問開始, 訪問開始 <= 訪問終了, 訪問開始 <= 報告開始,
/// 訪問終了 <= 報告終了, 報告開始 <= 報告終了。
class CampaignDraft {
  const CampaignDraft({
    required this.title,
    required this.storeName,
    required this.platforms,
    required this.rewardDescription,
    required this.rewardValueJpy,
    required this.quota,
    required this.applyEndDate,
    required this.visitStartDate,
    required this.visitEndDate,
    required this.postStartDate,
    required this.postEndDate,
    required this.requiredContent,
    this.genreId,
    this.hashtags = const <String>[],
    this.criteria,
    this.prefectureId,
    this.cityId,
    this.latitude,
    this.longitude,
    this.nearestStationId,
  });

  final String title;
  final String storeName;
  final Set<CampaignPlatform> platforms;
  final String rewardDescription;

  /// 提供内容の想定価格（円）。一覧の並び順・検索に使われる。
  final int? rewardValueJpy;

  final int? quota;
  final DateTime applyEndDate;
  final DateTime visitStartDate;
  final DateTime visitEndDate;
  final DateTime postStartDate;
  final DateTime postEndDate;
  final String requiredContent;
  final int? genreId;
  final List<String> hashtags;

  /// 応募条件（FR-CMP-04）。null は「条件なし＝全員が応募できる」。
  final Criteria? criteria;

  // 店舗プロフィールから引き継ぐ所在地スナップショット（FR-CMP-02）。
  final int? prefectureId;
  final int? cityId;
  final double? latitude;
  final double? longitude;
  final int? nearestStationId;

  /// 入力の不備を日本語で返す。問題がなければ null。
  String? validate({DateTime? now}) {
    final DateTime today = _dateOnly(now ?? DateTime.now());
    if (title.trim().isEmpty) {
      return '案件タイトルを入力してください。';
    }
    if (storeName.trim().isEmpty) {
      return '店舗名を入力してください。';
    }
    if (platforms.isEmpty) {
      return '投稿対象の SNS を 1 つ以上選んでください。';
    }
    if (rewardDescription.trim().isEmpty) {
      return '提供内容を入力してください。';
    }
    if (rewardValueJpy == null || rewardValueJpy! < 0) {
      return '提供内容の想定価格を 0 円以上で入力してください。';
    }
    if (quota == null || quota! < 1) {
      return '募集人数を 1 人以上で入力してください。';
    }
    if (requiredContent.trim().isEmpty) {
      return '必須投稿内容を入力してください。';
    }
    if (_dateOnly(applyEndDate).isBefore(today)) {
      return '応募締切日は今日以降にしてください。';
    }
    if (!_dateOnly(visitStartDate).isAfter(_dateOnly(applyEndDate))) {
      return '訪問開始日は応募締切日の翌日以降にしてください。';
    }
    if (_dateOnly(visitEndDate).isBefore(_dateOnly(visitStartDate))) {
      return '訪問終了日は訪問開始日以降にしてください。';
    }
    if (_dateOnly(postStartDate).isBefore(_dateOnly(visitStartDate))) {
      return '報告開始日は訪問開始日以降にしてください。';
    }
    if (_dateOnly(postEndDate).isBefore(_dateOnly(postStartDate))) {
      return '報告終了日は報告開始日以降にしてください。';
    }
    if (_dateOnly(postEndDate).isBefore(_dateOnly(visitEndDate))) {
      return '報告終了日は訪問終了日以降にしてください。';
    }
    return null;
  }

  /// 表示・保存用に正規化したハッシュタグ。
  ///
  /// 先頭に `#` を付け、空白と重複を除く。広告表記タグは
  /// サーバー側で自動付与されるため、ここでは除外する。
  List<String> get normalizedHashtags {
    final List<String> result = <String>[];
    for (final String raw in hashtags) {
      final String trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == '#') {
        continue;
      }
      final String tag = trimmed.startsWith('#') ? trimmed : '#$trimmed';
      if (tag.toUpperCase() == adDisclosureTag) {
        continue;
      }
      if (!result.contains(tag)) {
        result.add(tag);
      }
    }
    return result;
  }

  /// campaigns テーブルへの INSERT 用 JSON。
  ///
  /// [publish] が false のときは下書き（status = draft）として保存する。
  /// 応募開始はどちらの場合も [now]（公開時に締切より前であることは
  /// DB の期間制約が検査する）。
  Map<String, dynamic> toInsertJson({
    required String clientId,
    required bool publish,
    DateTime? now,
  }) {
    final DateTime applyStartAt = now ?? DateTime.now();
    return <String, dynamic>{
      'client_id': clientId,
      'status': publish ? 'recruiting' : 'draft',
      'title': title.trim(),
      'store_name_snapshot': storeName.trim(),
      'genre_id': genreId,
      'reward_description': rewardDescription.trim(),
      'reward_value_jpy': rewardValueJpy,
      'quota': quota,
      'platforms':
          platforms.map((CampaignPlatform p) => p.wireName).toList()..sort(),
      'apply_start_at': _toWire(applyStartAt),
      'apply_end_at': _toWire(_endOfDay(applyEndDate)),
      'visit_start_at': _toWire(_dateOnly(visitStartDate)),
      'visit_end_at': _toWire(_endOfDay(visitEndDate)),
      'post_start_at': _toWire(_dateOnly(postStartDate)),
      'post_end_at': _toWire(_endOfDay(postEndDate)),
      'required_content': requiredContent.trim(),
      'prefecture_id': prefectureId,
      'city_id': cityId,
      'latitude': latitude,
      'longitude': longitude,
      'nearest_station_id': nearestStationId,
      'published_at': publish ? _toWire(applyStartAt) : null,
      ...?_criteriaJson(),
    };
  }

  /// campaigns テーブルへの UPDATE 用 JSON（FR-CMP-13）。
  ///
  /// 状態と応募開始日時は編集で変えない。応募後に変更できない項目
  /// （条件・人数・期間・投稿対象）もそのまま送り、可否の判定は
  /// サーバー側のトリガーに委ねる（AGENTS.md R-8）。
  Map<String, dynamic> toUpdateJson() => <String, dynamic>{
        'title': title.trim(),
        'store_name_snapshot': storeName.trim(),
        'genre_id': genreId,
        'reward_description': rewardDescription.trim(),
        'reward_value_jpy': rewardValueJpy,
        'quota': quota,
        'platforms':
            platforms.map((CampaignPlatform p) => p.wireName).toList()..sort(),
        'apply_end_at': _toWire(_endOfDay(applyEndDate)),
        'visit_start_at': _toWire(_dateOnly(visitStartDate)),
        'visit_end_at': _toWire(_endOfDay(visitEndDate)),
        'post_start_at': _toWire(_dateOnly(postStartDate)),
        'post_end_at': _toWire(_endOfDay(postEndDate)),
        'required_content': requiredContent.trim(),
        'prefecture_id': prefectureId,
        'city_id': cityId,
        'latitude': latitude,
        'longitude': longitude,
        'nearest_station_id': nearestStationId,
        ...?_criteriaJson(),
      };

  /// 条件が未設定なら列自体を送らず、DB の既定値（条件なし）に任せる。
  Map<String, dynamic>? _criteriaJson() => criteria == null
      ? null
      : <String, dynamic>{'criteria': criteria!.toJson()};

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59);

  /// timestamptz へはオフセット付きで送る。ローカル時刻の素の文字列を
  /// 送るとサーバー側で UTC と解釈されてずれるため、UTC へ変換する。
  static String _toWire(DateTime value) => value.toUtc().toIso8601String();
}
