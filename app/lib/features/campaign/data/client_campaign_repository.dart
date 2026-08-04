import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../search/domain/criteria.dart';
import '../../search/domain/masked_count.dart';
import '../domain/campaign_draft.dart';
import '../domain/client_campaign.dart';
import '../domain/criteria_template.dart';

/// 案件画像を置く Storage バケット（0016_campaign_images_and_edit.sql）。
const String campaignImagesBucket = 'campaign-images';

/// アップロードする画像 1 枚分。プラットフォーム依存の型を持ち込まない。
class CampaignImageData {
  const CampaignImageData({
    required this.bytes,
    required this.contentType,
  });

  final Uint8List bytes;

  /// `image/jpeg` など。バケットの `allowed_mime_types` と揃える。
  final String contentType;

  /// 保存パスに使う拡張子。
  String get extension => switch (contentType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

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
  ///
  /// 画像は案件 id をフォルダ名に使うため、案件行の作成後にアップロードする。
  Future<String> create(
    CampaignDraft draft, {
    required bool publish,
    List<CampaignImageData> images = const <CampaignImageData>[],
  }) async {
    final String userId = _requireUserId();
    try {
      final Map<String, dynamic> inserted = await _client
          .from('campaigns')
          .insert(draft.toInsertJson(clientId: userId, publish: publish))
          .select('id')
          .single();
      final String campaignId = inserted['id'] as String;

      await _replaceHashtags(campaignId, draft.normalizedHashtags);
      for (int i = 0; i < images.length; i++) {
        await addImage(campaignId, images[i], sortOrder: i);
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

  /// 案件を更新する（FR-CMP-13）。
  ///
  /// 応募が入ったあとの募集条件・人数・期間・投稿対象の変更は
  /// サーバー側のトリガーが拒否する。ここでの出し分けは UX のためであり、
  /// 担保はサーバー側にある（AGENTS.md R-8）。
  Future<void> update(String campaignId, CampaignDraft draft) async {
    try {
      await _client
          .from('campaigns')
          .update(draft.toUpdateJson())
          .eq('id', campaignId);
      await _replaceHashtags(campaignId, draft.normalizedHashtags);
      AppLogger.info('client_campaign.updated',
          <String, Object?>{'campaign_id': campaignId});
    } on Object catch (e, s) {
      final AppFailure failure = e.toString().contains('応募者がいるため')
          ? const AppFailure(FailureKind.conflict,
              '応募者がいるため、募集条件・募集人数・期間・投稿対象は変更できません。案内文の変更のみ保存できます。')
          : AppFailure.from(e);
      AppLogger.error('client_campaign.update_failed', failure.code, s);
      throw failure;
    }
  }

  /// 案件を取り下げる（FR-CMP-13）。応募者への通知はサーバー側で行う。
  Future<void> cancel(String campaignId, {String? reason}) async {
    try {
      await _client.rpc<dynamic>(
        'cancel_campaign',
        params: <String, dynamic>{
          'p_campaign_id': campaignId,
          'p_reason': reason,
        },
      );
      AppLogger.info('client_campaign.cancelled',
          <String, Object?>{'campaign_id': campaignId});
    } on Object catch (e, s) {
      final AppFailure failure = e.toString().contains('取り下げできません')
          ? const AppFailure(
              FailureKind.conflict, 'この状態の案件は取り下げできません。一覧を更新して状態を確認してください。')
          : AppFailure.from(e);
      AppLogger.error('client_campaign.cancel_failed', failure.code, s);
      throw failure;
    }
  }

  /// 募集を一時停止する（FR-CMP-13）。応募は残したまま新規応募だけを止める。
  Future<void> suspend(String campaignId, {String? reason}) =>
      _callStatusRpc(
        'suspend_campaign',
        <String, dynamic>{'p_campaign_id': campaignId, 'p_reason': reason},
        logKey: 'suspend',
        conflictMessage: '募集中の案件だけを一時停止できます。一覧を更新して状態を確認してください。',
      );

  /// 一時停止した募集を再開する。
  ///
  /// 運営が停止した案件はサーバー側で拒否される（FR-ADM-04）。
  Future<void> resume(String campaignId) => _callStatusRpc(
        'resume_campaign',
        <String, dynamic>{'p_campaign_id': campaignId},
        logKey: 'resume',
        conflictMessage: '一時停止中の案件だけを再開できます。一覧を更新して状態を確認してください。',
      );

  /// 案件を複製して下書きを作る（FR-CMP-15）。
  ///
  /// 画像は Storage 上でコピーする。1 枚でも失敗したら案件ごと作り直させる
  /// のではなく、コピーできた分だけを持つ下書きとして残す（作り直しは編集で行える）。
  Future<String> duplicate(EditableCampaign source, {DateTime? now}) async {
    final String campaignId =
        await create(source.draft.asDuplicate(now: now), publish: false);
    for (int i = 0; i < source.images.length; i++) {
      final String from = source.images[i];
      final String to = '$campaignId/${from.split('/').last}';
      try {
        await _client.storage.from(campaignImagesBucket).copy(from, to);
        await _client.from('campaign_images').insert(<String, dynamic>{
          'campaign_id': campaignId,
          'storage_path': to,
          'sort_order': i,
        });
      } on Object catch (e, s) {
        AppLogger.error(
            'client_campaign.duplicate_image_failed', AppFailure.from(e).code, s);
      }
    }
    AppLogger.info('client_campaign.duplicated',
        <String, Object?>{'campaign_id': campaignId});
    return campaignId;
  }

  /// 状態を変える RPC の共通処理。
  ///
  /// サーバー側の状態チェックに引っかかった場合は、原因と次の行動を含む
  /// 文言に置き換える（AGENTS.md §3）。
  Future<void> _callStatusRpc(
    String function,
    Map<String, dynamic> params, {
    required String logKey,
    required String conflictMessage,
  }) async {
    try {
      await _client.rpc<dynamic>(function, params: params);
      AppLogger.info('client_campaign.$logKey',
          <String, Object?>{'campaign_id': params['p_campaign_id']});
    } on Object catch (e, s) {
      final String raw = e.toString();
      final AppFailure failure;
      if (raw.contains('運営により停止されています')) {
        failure = const AppFailure(FailureKind.unauthorized,
            'この案件は運営により停止されています。運営にお問い合わせください。');
      } else if (raw.contains('だけを')) {
        failure = AppFailure(FailureKind.conflict, conflictMessage);
      } else {
        failure = AppFailure.from(e);
      }
      AppLogger.error('client_campaign.${logKey}_failed', failure.code, s);
      throw failure;
    }
  }

  /// 条件テンプレートの一覧（FR-CMP-16）。
  Future<List<CriteriaTemplate>> listTemplates() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('criteria_templates')
          .select('id, name, criteria, created_at')
          .order('created_at', ascending: false);
      return rows.map(CriteriaTemplate.fromJson).toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.template_list_failed', failure.code, s);
      throw failure;
    }
  }

  /// 条件テンプレートを保存する。同名があれば上書きする。
  Future<void> saveTemplate(String name, Criteria criteria) async {
    final String userId = _requireUserId();
    try {
      await _client.from('criteria_templates').upsert(
        <String, dynamic>{
          'client_id': userId,
          'name': name.trim(),
          'criteria': criteria.toJson(),
        },
        onConflict: 'client_id,name',
      );
    } on Object catch (e, s) {
      final AppFailure failure = e.toString().contains('criteria:')
          ? const AppFailure(
              FailureKind.conflict, 'この条件は保存できません。条件の指標と値を確認してください。')
          : AppFailure.from(e);
      AppLogger.error('client_campaign.template_save_failed', failure.code, s);
      throw failure;
    }
  }

  /// 条件テンプレートを削除する。
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _client.from('criteria_templates').delete().eq('id', templateId);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.template_delete_failed', failure.code, s);
      throw failure;
    }
  }

  /// 任意ハッシュタグを入れ替える。
  ///
  /// 広告表記タグ（`is_mandatory`）は RLS が削除を弾くため、
  /// ここで消そうとしても残る。サーバー側の保証に委ねて条件を書かない。
  Future<void> _replaceHashtags(String campaignId, List<String> tags) async {
    await _client
        .from('campaign_hashtags')
        .delete()
        .eq('campaign_id', campaignId);
    if (tags.isNotEmpty) {
      await _client.from('campaign_hashtags').insert(<Map<String, dynamic>>[
        for (final String tag in tags)
          <String, dynamic>{'campaign_id': campaignId, 'tag': tag},
      ]);
    }
  }

  /// 案件画像を 1 枚追加する（FR-CMP-11）。
  ///
  /// パスは `{案件id}/{連番}.{拡張子}`。先頭フォルダで所有者を判定する
  /// Storage ポリシー（0016）に合わせる。
  Future<String> addImage(
    String campaignId,
    CampaignImageData image, {
    required int sortOrder,
  }) async {
    try {
      final String path = '$campaignId/'
          '${DateTime.now().millisecondsSinceEpoch}_$sortOrder.${image.extension}';
      await _client.storage.from(campaignImagesBucket).uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(contentType: image.contentType),
          );
      await _client.from('campaign_images').insert(<String, dynamic>{
        'campaign_id': campaignId,
        'storage_path': path,
        'sort_order': sortOrder,
      });
      return path;
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.image_upload_failed', failure.code, s);
      throw failure;
    }
  }

  /// 案件画像を 1 枚削除する。
  Future<void> removeImage(String campaignId, String storagePath) async {
    try {
      await _client
          .from('campaign_images')
          .delete()
          .eq('campaign_id', campaignId)
          .eq('storage_path', storagePath);
      await _client.storage
          .from(campaignImagesBucket)
          .remove(<String>[storagePath]);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.image_delete_failed', failure.code, s);
      throw failure;
    }
  }

  /// 編集画面で使う 1 件分の全項目。自分の案件のみ RLS で返る。
  Future<EditableCampaign> fetchForEdit(String campaignId) async {
    try {
      final Map<String, dynamic> row = await _client
          .from('campaigns')
          .select('id, status, title, store_name_snapshot, genre_id, '
              'reward_description, reward_value_jpy, quota, platforms, '
              'criteria, apply_end_at, visit_start_at, visit_end_at, '
              'post_start_at, post_end_at, required_content, '
              'prefecture_id, city_id, latitude, longitude, nearest_station_id')
          .eq('id', campaignId)
          .single();
      final List<Map<String, dynamic>> tags = await _client
          .from('campaign_hashtags')
          .select('tag, is_mandatory')
          .eq('campaign_id', campaignId);
      final List<Map<String, dynamic>> images = await _client
          .from('campaign_images')
          .select('storage_path, sort_order')
          .eq('campaign_id', campaignId)
          .order('sort_order');
      final int applicantCount = await _client
          .from('applications')
          .select('id')
          .eq('campaign_id', campaignId)
          .count()
          .then((PostgrestResponse<dynamic> r) => r.count);
      return EditableCampaign.fromRows(
        row: row,
        tags: tags,
        images: images,
        applicantCount: applicantCount,
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.fetch_edit_failed', failure.code, s);
      throw failure;
    }
  }

  /// 画像を表示するための署名付き URL。バケットは非公開のため毎回発行する。
  Future<List<String>> signedImageUrls(List<String> paths) async {
    if (paths.isEmpty) {
      return <String>[];
    }
    try {
      final List<SignedUrlResult> signed = await _client.storage
          .from(campaignImagesBucket)
          .createSignedUrlsResult(paths, 3600);
      // 署名できなかったパス（実体が消えている等）は空文字にして順序を保つ。
      // 呼び出し側は「読み込めない画像」として扱う。
      return signed
          .map((SignedUrlResult r) =>
              r is SignedUrlSuccess ? r.signedUrl : '')
          .toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.signed_url_failed', failure.code, s);
      throw failure;
    }
  }

  /// 条件に一致する投稿者数（FR-CMP-05）。
  ///
  /// 戻り値は k-匿名性で丸められている可能性がある。
  /// `masked` が true のとき、**実数を推定して表示してはならない**。
  Future<MaskedCount> countMatching(Criteria criteria) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'count_matching_creators',
        params: <String, dynamic>{'p_criteria': criteria.toJson()},
      );
      return MaskedCount.fromJson(result as Map<String, dynamic>);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('client_campaign.count_failed', failure.code, s);
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
              'post_start_at, post_end_at, published_at, created_at, '
              'suspended_by')
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

/// 編集画面が読む案件 1 件。保存後は invalidate して読み直す。
final FutureProviderFamily<EditableCampaign, String> editableCampaignProvider =
    FutureProvider.family<EditableCampaign, String>(
  (Ref ref, String campaignId) =>
      ref.watch(clientCampaignRepositoryProvider).fetchForEdit(campaignId),
);

/// 保存済みの条件テンプレート（FR-CMP-16）。
final FutureProvider<List<CriteriaTemplate>> criteriaTemplatesProvider =
    FutureProvider<List<CriteriaTemplate>>(
  (Ref ref) => ref.watch(clientCampaignRepositoryProvider).listTemplates(),
);

/// 案件画像の署名付き URL。有効期限があるため autoDispose で持ち回さない。
final AutoDisposeFutureProviderFamily<List<String>, String>
    campaignImageUrlsProvider =
    FutureProvider.autoDispose.family<List<String>, String>(
  (Ref ref, String pathsCsv) => ref
      .watch(clientCampaignRepositoryProvider)
      .signedImageUrls(pathsCsv.isEmpty ? <String>[] : pathsCsv.split(',')),
);
