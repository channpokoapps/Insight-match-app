import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/sns_link_status.dart';

/// SNS 連携状態の取得。
///
/// 実数値は `private` スキーマにあり、この経路では取得できない。
/// RPC `get_my_sns_status` が返すのは状態と最終同期日時のみ。
class SnsLinkRepository {
  const SnsLinkRepository(this._client);

  final SupabaseClient _client;

  Future<List<SnsLinkStatus>> fetchMyStatus() async {
    try {
      final dynamic result = await _client.rpc<dynamic>('get_my_sns_status');
      final List<dynamic> rows = (result as List<dynamic>?) ?? <dynamic>[];
      return rows
          .map((dynamic e) =>
              SnsLinkStatus.fromJson(Map<String, dynamic>.from(e as Map<dynamic, dynamic>)))
          .toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('sns_link.fetch_failed', failure.code, s);
      throw failure;
    }
  }
}

final Provider<SnsLinkRepository> snsLinkRepositoryProvider =
    Provider<SnsLinkRepository>(
  (Ref ref) => SnsLinkRepository(ref.watch(supabaseClientProvider)),
);

final FutureProvider<List<SnsLinkStatus>> mySnsLinkStatusProvider =
    FutureProvider<List<SnsLinkStatus>>(
  (Ref ref) => ref.watch(snsLinkRepositoryProvider).fetchMyStatus(),
);
