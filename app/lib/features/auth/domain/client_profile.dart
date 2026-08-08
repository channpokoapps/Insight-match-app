/// PR依頼者（店舗・企業）のプロフィール（FR-AUTH-07）。
///
/// 店舗名・所在地・紹介文は案件詳細で投稿者にも表示される。
/// 連絡先メールは運営との連絡にのみ使い、投稿者向けのビュー
/// （`v_client_public`）には含まれない。
class ClientProfile {
  const ClientProfile({
    required this.storeName,
    this.genreIds = const <int>[],
    this.genreOtherText,
    this.postalCode,
    this.prefectureId,
    this.cityId,
    this.addressLine,
    this.latitude,
    this.longitude,
    this.nearestStationId,
    this.contactEmail,
    this.description,
  });

  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
        storeName: json['store_name'] as String? ?? '',
        genreIds: <int>[
          for (final Object? id in json['genre_ids'] as List<dynamic>? ??
              const <dynamic>[])
            if (id is int) id,
        ],
        genreOtherText: json['genre_other_text'] as String?,
        postalCode: json['postal_code'] as String?,
        prefectureId: json['prefecture_id'] as int?,
        cityId: json['city_id'] as int?,
        addressLine: json['address_line'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        nearestStationId: json['nearest_station_id'] as int?,
        contactEmail: json['contact_email'] as String?,
        description: json['description'] as String?,
      );

  final String storeName;
  final List<int> genreIds;
  final String? genreOtherText;
  final String? postalCode;
  final int? prefectureId;
  final int? cityId;
  final String? addressLine;
  final double? latitude;
  final double? longitude;
  final int? nearestStationId;
  final String? contactEmail;
  final String? description;
}
