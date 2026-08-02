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
          .map((dynamic e) => SnsLinkStatus.fromJson(
              Map<String, dynamic>.from(e as Map<dynamic, dynamic>)))
          .toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('sns_link.fetch_failed', failure.code, s);
      throw failure;
    }
  }

  /// Instagram の認可 URL を取得する（連携開始）。
  ///
  /// URL の発行と state の署名は Edge Function `meta-oauth` が行う。
  /// 戻り値の URL を外部ブラウザで開くと、認可完了後に
  /// サーバー側でトークンが暗号化保存される（トークンはアプリを経由しない。
  /// 要件 9-4 X-3）。
  Future<Uri> startInstagramLink() async {
    try {
      final FunctionResponse res = await _client.functions.invoke(
        'meta-oauth',
        body: <String, String>{'action': 'start'},
      );
      final Map<String, dynamic> body =
          Map<String, dynamic>.from(res.data as Map<dynamic, dynamic>);
      final String? url = body['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const AppFailure(
          FailureKind.unknown,
          '連携を開始できませんでした。時間をおいて再度お試しください。',
        );
      }
      return Uri.parse(url);
    } on AppFailure {
      rethrow;
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('sns_link.start_failed', failure.code, s);
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
