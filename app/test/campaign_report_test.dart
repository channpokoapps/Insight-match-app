import 'package:app2/features/report/domain/campaign_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CampaignReport', () {
    test('サーバが available:false を返したら理由付きで非表示にする', () {
      final CampaignReport report = CampaignReport.fromJson(<String, dynamic>{
        'available': false,
        'reason': 'k_anonymity',
        'message': 'サーバ側の文言',
      });
      expect(report, isA<ReportUnavailable>());
      expect(
        (report as ReportUnavailable).reason,
        ReportUnavailableReason.kAnonymity,
      );
    });

    test('サーバが available:true でも参加人数が k 未満なら表示しない', () {
      // サーバ側の判定漏れを想定した多層防御の確認
      final CampaignReport report = CampaignReport.fromJson(<String, dynamic>{
        'available': true,
        'participant_count': kAnonymityThreshold - 1,
        'metrics': <String, dynamic>{
          'reach': <String, dynamic>{'median': 1200, 'total': 4800},
        },
      });
      expect(report, isA<ReportUnavailable>());
      expect(
        (report as ReportUnavailable).reason,
        ReportUnavailableReason.kAnonymity,
      );
    });

    test('k 以上なら集計値を読み出せる', () {
      final CampaignReport report = CampaignReport.fromJson(<String, dynamic>{
        'available': true,
        'participant_count': 8,
        'metrics': <String, dynamic>{
          'reach': <String, dynamic>{
            'median': 1500,
            'total': 12000,
            'histogram': <dynamic>[
              <String, dynamic>{'from': 0, 'to': 2000, 'count': 5},
              <String, dynamic>{'from': 2000, 'to': 4000, 'count': 3},
            ],
          },
        },
      });
      expect(report, isA<ReportAvailable>());
      final ReportAvailable available = report as ReportAvailable;
      expect(available.participantCount, 8);
      expect(available[ReportMetricKey.reach]?.median, 1500);
      expect(available[ReportMetricKey.reach]?.histogram.length, 2);
      expect(available[ReportMetricKey.likes], isNull);
    });

    test('未知の理由でも落ちずに非表示扱いになる', () {
      final CampaignReport report = CampaignReport.fromJson(<String, dynamic>{
        'available': false,
      });
      expect(
        (report as ReportUnavailable).reason,
        ReportUnavailableReason.unknown,
      );
      expect(report.message, isNotEmpty);
    });
  });

  group('ReportBin', () {
    test('区間ラベルを組み立てる', () {
      const ReportBin bin = ReportBin(from: 1000, to: 2000, count: 5);
      expect(bin.label, '1000〜2000');
    });
  });
}
