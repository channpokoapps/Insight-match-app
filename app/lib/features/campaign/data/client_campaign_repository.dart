import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/campaign_draft.dart';
import '../domain/client_campaign.dart';

/// 案件作成フォームへ引き継ぐ店舗プロフィールの初期値（FR-CMP-02）。
class StoreDefaults {
  const StoreDefaults({
    required this.storeName,
    this.genreId,
    this.prefectureId,
    this.cityId,
    this.latitude,
    this.longitude,
    this.nearestStationId,
  });

  final String storeName;
  final int? genreId;
  final int? prefectureId;
  final int? cityId;
  final double? latitude;
  final double? longitude;
  final int? nearestStationId;
}

/// PR依頼者による案件の作成・管理のサーバアクセス。
///
/// 自分の案件は RLS（`campaigns_owner_all`）で行が絞られるため
/// テーブルを直接読み書きしてよい。応募者側の情報には触れない。
class ClientCampaignRepository {
  const ClientCampaignRepository(this._client);

  final SupabaseClient _client;

  String _requireUserId() {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AppFailure(
          FailureKind.unauthorized, 'ログインの有効期限が切れました。ログインし直してください。');
    }
    return userId;
  }

  /// 店舗プロフィールから案件フォームの初期値を引く。
  Future<StoreDefaults> fetchStoreDefaults() async {
    final String userId = _requireUserId();
    try {
      final Map<String, dynamic>? row = await _client
          .from('client_profiles')
          .select('store_name, genre_ids, prefecture_id, city_id, '
              'latitude, longitude, nearest_station_id')
          .eq('user_id', userId)
          .maybeSingle();
      final List<int> genreIds = (row?['genre_ids'] as List<dynamic>? ??
              <dynamic>[])
          .map((dynamic e) => e as int)
          .toList();
      return StoreDefaults(
        storeName: row?['store_name'] as String? ?? '',
        genreId: genreIds.isEmpty ? null : genreIds.first,
        prefectureId: row?['prefecture_id'] as int?,
        cityId: row?['city_id'] as int?,
        latitude: (row?['latitude'] as num?)?.toDouble(),
        longitude: (row?['longitude'] as num?)?.toDouble(),
        nearestStationId: row?['nearest_station_id'] as int?,
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.defaults_failed', failure.code, s);
      throw failure;
    }
  }

  /// 案件を作成する。[publish] が false なら下書きとして保存する。
  ///
  /// 広告表記タグ（#PR）はサーバー側のトリガーが自動付与するため、
  /// ここでは任意タグだけを登録する。戻り値は作成した案件の id。
  Future<String> create(CampaignDraft draft, {required bool publish}) async {
    final String userId = _requireUserId();
    try {
      final Map<String, dynamic> inserted = await _client
          .from('campaigns')
          .insert(draft.toInsertJson(clientId: userId, publish: publish))
          .select('id')
          .single();
      final String campaignId = inserted['id'] as String;

      final List<String> tags = draft.normalizedHashtags;
      if (tags.isNotEmpty) {
        await _client.from('campaign_hashtags').insert(<Map<String, dynamic>>[
          for (final String tag in tags)
            <String, dynamic>{'campaign_id': campaignId, 'tag': tag},
        ]);
      }
      AppLogger.info('client_campaign.created', <String, Object?>{
        'campaign_id': campaignId,
        'publish': publish,
      });
      return campaignId;
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.create_failed', failure.code, s);
      throw failure;
    }
  }

  /// 自分の案件一覧を新しい順で返す。
  Future<List<ClientCampaign>> listOwn() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('campaigns')
          .select('id, status, title, reward_value_jpy, quota, platforms, '
              'apply_end_at, visit_start_at, visit_end_at, '
              'post_start_at, post_end_at, published_at, created_at')
          .order('created_at', ascending: false);
      return rows.map(ClientCampaign.fromJson).toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.list_failed', failure.code, s);
      throw failure;
    }
  }

  /// 下書きの案件を公開する。
  ///
  /// 応募開始を公開時点に更新するため、締切が過ぎた下書きは
  /// DB の期間制約（apply_start < apply_end）で拒否される。
  Future<void> publishDraft(String campaignId) async {
    try {
      final String nowWire = DateTime.now().toUtc().toIso8601String();
      final List<Map<String, dynamic>> updated = await _client
          .from('campaigns')
          .update(<String, dynamic>{
            'status': 'recruiting',
            'apply_start_at': nowWire,
            'published_at': nowWire,
          })
          .eq('id', campaignId)
          .eq('status', 'draft')
          .select('id');
      if (updated.isEmpty) {
        throw const AppFailure(FailureKind.conflict,
            'この案件は下書きではないため公開できません。一覧を更新して状態を確認してください。');
      }
      AppLogger.info('client_campaign.published',
          <String, Object?>{'campaign_id': campaignId});
    } on AppFailure {
      rethrow;
    } on Object catch (e, s) {
      // 応募開始を now に更新するため、締切超過は期間制約の違反として返る。
      final AppFailure failure = e.toString().contains('campaigns_')
          ? const AppFailure(FailureKind.conflict,
              '応募締切日を過ぎているため公開できません。締切日を変更した案件を作成し直してください。')
          : AppFailure.from(e);
      AppLogger.error('client_campaign.publish_failed', failure.code, s);
      throw failure;
    }
  }
}

final Provider<ClientCampaignRepository> clientCampaignRepositoryProvider =
    Provider<ClientCampaignRepository>(
  (Ref ref) => ClientCampaignRepository(ref.watch(supabaseClientProvider)),
);

/// 自分の案件一覧。作成・公開後は invalidate して更新する。
final FutureProvider<List<ClientCampaign>> ownCampaignsProvider =
    FutureProvider<List<ClientCampaign>>(
  (Ref ref) => ref.watch(clientCampaignRepositoryProvider).listOwn(),
);

/// 案件フォームの初期値（店舗プロフィールのスナップショット）。
final FutureProvider<StoreDefaults> storeDefaultsProvider =
    FutureProvider<StoreDefaults>(
  (Ref ref) => ref.watch(clientCampaignRepositoryProvider).fetchStoreDefaults(),
);
