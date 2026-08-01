/// k-匿名性のしきい値。サーバの `private.k_threshold()` と同じ値。
const int kAnonymityThreshold = 5;

/// 案件の成果レポート。
///
/// 参加人数が k（=5）未満のときは、合計値や中央値からでも個人の値が逆算できるため
/// 一切表示しない（AGENTS.md R-4 / OI-14）。
/// 「表示できる」「表示できない」を型で分け、画面側が数値へ到達する経路をなくす。
sealed class CampaignReport {
  const CampaignReport();

  /// RPC `get_campaign_report` の応答から組み立てる。
  ///
  /// サーバ側でも k 判定を行っているが、ここでも同じ判定をする。
  /// どちらか一方の実装ミスで実数値が露出することを避けるため（多層防御）。
  factory CampaignReport.fromJson(Map<String, dynamic> json) {
    if (json['available'] != true) {
      return ReportUnavailable(
        reason: ReportUnavailableReason.fromKey(json['reason'] as String?),
      );
    }

    final int participantCount = (json['participant_count'] as num?)?.toInt() ?? 0;
    if (participantCount < kAnonymityThreshold) {
      return const ReportUnavailable(reason: ReportUnavailableReason.kAnonymity);
    }

    final Map<String, dynamic> metrics = Map<String, dynamic>.from(
      (json['metrics'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
    );
    return ReportAvailable(
      participantCount: participantCount,
      metrics: <ReportMetricKey, ReportMetric>{
        for (final ReportMetricKey key in ReportMetricKey.values)
          if (metrics[key.key] != null)
            key: ReportMetric.fromJson(
              Map<String, dynamic>.from(metrics[key.key] as Map<dynamic, dynamic>),
            ),
      },
      generatedAt: json['generated_at'] == null
          ? null
          : DateTime.parse(json['generated_at'] as String),
    );
  }
}

class ReportAvailable extends CampaignReport {
  const ReportAvailable({
    required this.participantCount,
    required this.metrics,
    this.generatedAt,
  });

  /// k 以上であることが保証されている。
  final int participantCount;

  final Map<ReportMetricKey, ReportMetric> metrics;

  /// スナップショットの集計時点。インサイトの表示には必ず併記する。
  final DateTime? generatedAt;

  ReportMetric? operator [](ReportMetricKey key) => metrics[key];
}

class ReportUnavailable extends CampaignReport {
  const ReportUnavailable({required this.reason});

  final ReportUnavailableReason reason;

  String get message => reason.message;
}

enum ReportUnavailableReason {
  kAnonymity(
    'k_anonymity',
    '投稿数が5件未満のため、個人が特定されないようレポートを表示していません。',
  ),
  notCompleted('not_completed', '案件が完了するとレポートを表示できます。'),
  unknown('unknown', 'レポートを表示できません。');

  const ReportUnavailableReason(this.key, this.message);

  final String key;
  final String message;

  static ReportUnavailableReason fromKey(String? key) {
    for (final ReportUnavailableReason reason in ReportUnavailableReason.values) {
      if (reason.key == key) {
        return reason;
      }
    }
    return ReportUnavailableReason.unknown;
  }
}

/// レポートで扱う指標。RPC の `metrics` のキーと一致させる。
enum ReportMetricKey {
  reach('reach', 'リーチ'),
  likes('likes', 'いいね'),
  saves('saves', '保存');

  const ReportMetricKey(this.key, this.label);

  final String key;
  final String label;
}

/// 指標ごとの集計。個人の内訳は含まない。
class ReportMetric {
  const ReportMetric({
    required this.histogram,
    this.median,
    this.total,
  });

  factory ReportMetric.fromJson(Map<String, dynamic> json) => ReportMetric(
        median: (json['median'] as num?)?.toDouble(),
        total: (json['total'] as num?)?.toDouble(),
        histogram: <ReportBin>[
          for (final dynamic bin in (json['histogram'] as List<dynamic>?) ?? <dynamic>[])
            ReportBin.fromJson(Map<String, dynamic>.from(bin as Map<dynamic, dynamic>)),
        ],
      );

  final double? median;
  final double? total;

  /// 度数分布。5 未満のビンはサーバ側で隣に併合済み。
  final List<ReportBin> histogram;
}

/// 分布のひと区間。
class ReportBin {
  const ReportBin({
    required this.from,
    required this.to,
    required this.count,
  });

  factory ReportBin.fromJson(Map<String, dynamic> json) => ReportBin(
        from: (json['from'] as num?)?.toDouble() ?? 0,
        to: (json['to'] as num?)?.toDouble() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  final double from;
  final double to;

  /// サーバ側で 5 未満のビンは隣に併合済みのため、常に 5 以上。
  final int count;

  String get label => '${from.round()}〜${to.round()}';
}
