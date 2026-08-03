/// 案件一覧の1件分。
///
/// **応募条件（criteria）を含めないこと。**
/// 条件そのものが分かると、他の投稿者の分布推測や条件回避の材料になる。
class CampaignListItem {
  const CampaignListItem({
    required this.id,
    required this.title,
    required this.storeName,
    required this.rewardValueJpy,
    required this.applyEndAt,
    required this.postStartAt,
    required this.postEndAt,
    required this.isEligible,
    required this.hasApplied,
    this.rewardDescription,
    this.genreId,
    this.prefectureId,
    this.cityId,
    this.thumbnailPath,
  });

  factory CampaignListItem.fromJson(Map<String, dynamic> json) =>
      CampaignListItem(
        id: json['id'] as String,
        title: json['title'] as String,
        storeName: json['store_name'] as String,
        rewardDescription: json['reward_description'] as String?,
        rewardValueJpy: json['reward_value_jpy'] as int,
        applyEndAt: DateTime.parse(json['apply_end_at'] as String),
        postStartAt: DateTime.parse(json['post_start_at'] as String),
        postEndAt: DateTime.parse(json['post_end_at'] as String),
        isEligible: json['is_eligible'] as bool? ?? false,
        hasApplied: json['has_applied'] as bool? ?? false,
        genreId: json['genre_id'] as int?,
        prefectureId: json['prefecture_id'] as int?,
        cityId: json['city_id'] as int?,
        thumbnailPath: json['thumbnail_path'] as String?,
      );

  final String id;
  final String title;
  final String storeName;

  /// 応募条件を満たさない場合、サーバは値を送らないため null になる。
  final String? rewardDescription;

  final int rewardValueJpy;
  final DateTime applyEndAt;
  final DateTime postStartAt;
  final DateTime postEndAt;

  /// false の場合、詳細をモザイク表示にする。
  final bool isEligible;

  final bool hasApplied;
  final int? genreId;
  final int? prefectureId;
  final int? cityId;
  final String? thumbnailPath;
}

/// 案件詳細。
///
/// 条件を満たさない場合、`detail` は null になる。
/// これは「値を持っているが隠している」のではなく、**サーバが値を送っていない**状態。
class CampaignDetail {
  const CampaignDetail({
    required this.id,
    required this.title,
    required this.storeName,
    required this.rewardValueJpy,
    required this.applyEndAt,
    required this.isEligible,
    this.detail,
  });

  factory CampaignDetail.fromJson(Map<String, dynamic> json) => CampaignDetail(
        id: json['id'] as String,
        title: json['title'] as String,
        storeName: json['store_name'] as String,
        rewardValueJpy: json['reward_value_jpy'] as int,
        applyEndAt: DateTime.parse(json['apply_end_at'] as String),
        isEligible: json['is_eligible'] as bool? ?? false,
        detail: json['detail'] == null
            ? null
            : CampaignDetailBody.fromJson(
                json['detail'] as Map<String, dynamic>),
      );

  final String id;
  final String title;
  final String storeName;
  final int rewardValueJpy;
  final DateTime applyEndAt;
  final bool isEligible;
  final CampaignDetailBody? detail;
}

class CampaignDetailBody {
  const CampaignDetailBody({
    required this.rewardDescription,
    required this.requiredContent,
    required this.postStartAt,
    required this.postEndAt,
    required this.hashtags,
    required this.images,
    this.latitude,
    this.longitude,
    this.nearestStationId,
  });

  factory CampaignDetailBody.fromJson(Map<String, dynamic> json) =>
      CampaignDetailBody(
        rewardDescription: json['reward_description'] as String,
        requiredContent: json['required_content'] as String,
        postStartAt: DateTime.parse(json['post_start_at'] as String),
        postEndAt: DateTime.parse(json['post_end_at'] as String),
        hashtags: (json['hashtags'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e as String)
            .toList(),
        images: (json['images'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e as String)
            .toList(),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        nearestStationId: json['nearest_station_id'] as int?,
      );

  final String rewardDescription;
  final String requiredContent;
  final DateTime postStartAt;
  final DateTime postEndAt;
  final List<String> hashtags;
  final List<String> images;
  final double? latitude;
  final double? longitude;
  final int? nearestStationId;
}
