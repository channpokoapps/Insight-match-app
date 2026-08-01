import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/application.dart';

/// 応募の参照・操作。
///
/// PR依頼者側は `v_applications_for_client` 経由でのみ読む。
/// `applications` を直接 SELECT しても RLS で 0 件になる。
class ApplicationRepository {
  const ApplicationRepository(this._client);

  final SupabaseClient _client;

  /// PR依頼者：自分の案件への応募一覧。投稿者は連番でしか識別できない。
  Future<List<ApplicationForClient>> listForClient(String campaignId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('v_applications_for_client')
          .select(
            'id, campaign_id, alias_no, status, created_at, '
            'has_submission, is_post_verified, message',
          )
          .eq('campaign_id', campaignId)
          .order('alias_no');
      return rows.map(ApplicationForClient.fromJson).toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('application.list_for_client_failed', failure.code, s);
      throw failure;
    }
  }

  /// 投稿者：自分の応募一覧。
  Future<List<MyApplication>> listMine() async {
    try {
      final dynamic result = await _client.rpc<dynamic>('list_my_applications');
      final List<dynamic> rows = (result as List<dynamic>?) ?? <dynamic>[];
      return rows
          .map((dynamic e) => MyApplication.fromJson(
              Map<String, dynamic>.from(e as Map<dynamic, dynamic>)))
          .toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('application.list_mine_failed', failure.code, s);
      throw failure;
    }
  }

  /// PR依頼者：採用 / 見送りの決定。判定と権限確認はサーバ側で再実行される。
  Future<void> decide({
    required String applicationId,
    required bool accept,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'decide_application',
        params: <String, dynamic>{
          'p_application_id': applicationId,
          'p_decision': accept ? 'matched' : 'rejected',
        },
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('application.decide_failed', failure.code, s);
      throw failure;
    }
  }
}

final Provider<ApplicationRepository> applicationRepositoryProvider =
    Provider<ApplicationRepository>(
  (Ref ref) => ApplicationRepository(ref.watch(supabaseClientProvider)),
);

final FutureProviderFamily<List<ApplicationForClient>, String>
    applicationsForClientProvider =
    FutureProvider.family<List<ApplicationForClient>, String>(
  (Ref ref, String campaignId) =>
      ref.watch(applicationRepositoryProvider).listForClient(campaignId),
);

final FutureProvider<List<MyApplication>> myApplicationsProvider =
    FutureProvider<List<MyApplication>>(
  (Ref ref) => ref.watch(applicationRepositoryProvider).listMine(),
);
