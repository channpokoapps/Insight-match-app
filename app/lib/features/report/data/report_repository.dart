import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/campaign_report.dart';

/// 成果レポートの取得。
///
/// 集計は `private` スキーマのデータから RPC 内で行われる。
/// クライアントに届くのは k-匿名性を満たした集計値のみ。
class ReportRepository {
  const ReportRepository(this._client);

  final SupabaseClient _client;

  Future<CampaignReport> fetch(String campaignId) async {
    try {
      final dynamic result = await _client.rpc<dynamic>(
        'get_campaign_report',
        params: <String, dynamic>{'p_campaign_id': campaignId},
      );
      if (result == null) {
        return const ReportUnavailable(reason: ReportUnavailableReason.unknown);
      }
      return CampaignReport.fromJson(
        Map<String, dynamic>.from(result as Map<dynamic, dynamic>),
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('report.fetch_failed', failure.code, s);
      throw failure;
    }
  }
}

final Provider<ReportRepository> reportRepositoryProvider =
    Provider<ReportRepository>(
  (Ref ref) => ReportRepository(ref.watch(supabaseClientProvider)),
);

final FutureProviderFamily<CampaignReport, String> campaignReportProvider =
    FutureProvider.family<CampaignReport, String>(
  (Ref ref, String campaignId) =>
      ref.watch(reportRepositoryProvider).fetch(campaignId),
);
