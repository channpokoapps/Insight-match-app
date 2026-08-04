import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../search/domain/campaign_filter.dart';
import '../../search/domain/criteria.dart';
import '../../search/domain/masked_count.dart';
import '../domain/campaign.dart';

/// 案件に関するサーバアクセス。
///
/// テーブルを直接 select せず、必ず RPC / 専用ビューを経由する。
/// `campaigns` テーブルには投稿者向けの RLS ポリシーが存在しないため、
/// 直接アクセスしても 0 件が返るだけになる。
class CampaignRepository {
  const CampaignRepository(this._client);

  final SupabaseClient _client;

  /// 投稿者向けの案件一覧。
  ///
  /// 絞り込み条件はサーバ側でも再評価される。応募条件を満たさない案件の
  /// 報酬内容は、そもそも返ってこない（0010 / 0014）。
  Future<List<CampaignListItem>> listForCreator({
    CampaignFilter filter = const CampaignFilter(),
    bool includeIneligible = true,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'list_campaigns_for_creator',
        params: <String, dynamic>{
          'p_prefecture_ids': CampaignFilter.toParam(filter.prefectureIds),
          'p_city_ids': CampaignFilter.toParam(filter.cityIds),
          'p_line_ids': CampaignFilter.toParam(filter.lineIds),
          'p_station_ids': CampaignFilter.toParam(filter.stationIds),
          'p_genre_ids': CampaignFilter.toParam(filter.genreIds),
          'p_min_reward': filter.minReward,
          'p_include_ineligible': includeIneligible,
          'p_sort': filter.sort.key,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      return (result as List<dynamic>)
          .map((dynamic e) =>
              CampaignListItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('campaign.list_failed', failure.code, s);
      throw failure;
    }
  }

  /// 案件詳細。条件を満たさない場合 `detail` は null で返る。
  Future<CampaignDetail> getDetail(String campaignId) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'get_campaign_detail',
        params: <String, dynamic>{'p_campaign_id': campaignId},
      );
      return CampaignDetail.fromJson(result as Map<String, dynamic>);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('campaign.detail_failed', failure.code, s);
      throw failure;
    }
  }

  /// 応募する。
  ///
  /// 条件充足の判定はサーバ側で再度行われる。
  /// クライアントで `isEligible` を見て出し分けているのは UX のためであり、
  /// これを迂回しても応募は成立しない。
  Future<String> apply(String campaignId, {String? message}) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'apply_to_campaign',
        params: <String, dynamic>{
          'p_campaign_id': campaignId,
          'p_message': message,
        },
      );
      AppLogger.info(
          'campaign.applied', <String, Object?>{'campaign_id': campaignId});
      return result as String;
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('campaign.apply_failed', failure.code, s);
      throw failure;
    }
  }

  /// 条件に一致する投稿者数（PR依頼者向け）。
  ///
  /// 戻り値は丸められている可能性がある。`masked` が true のとき、
  /// **実数を推定して表示してはならない**。
  Future<MaskedCount> countMatchingCreators(Criteria criteria) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'count_matching_creators',
        params: <String, dynamic>{'p_criteria': criteria.toJson()},
      );
      return MaskedCount.fromJson(result as Map<String, dynamic>);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('campaign.count_failed', failure.code, s);
      throw failure;
    }
  }
}

final Provider<CampaignRepository> campaignRepositoryProvider =
    Provider<CampaignRepository>(
  (Ref ref) => CampaignRepository(ref.watch(supabaseClientProvider)),
);

/// 案件一覧。絞り込み条件が同じならキャッシュが効く。
final FutureProviderFamily<List<CampaignListItem>, CampaignFilter>
    campaignListProvider =
    FutureProvider.family<List<CampaignListItem>, CampaignFilter>(
  (Ref ref, CampaignFilter filter) =>
      ref.watch(campaignRepositoryProvider).listForCreator(filter: filter),
);

/// 案件一覧画面で選択中の絞り込み条件。
final NotifierProvider<CampaignFilterNotifier, CampaignFilter>
    campaignFilterProvider =
    NotifierProvider<CampaignFilterNotifier, CampaignFilter>(
  CampaignFilterNotifier.new,
);

class CampaignFilterNotifier extends Notifier<CampaignFilter> {
  @override
  CampaignFilter build() => const CampaignFilter();

  void apply(CampaignFilter filter) => state = filter;

  void clear() => state = const CampaignFilter();
}
