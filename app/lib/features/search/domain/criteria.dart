/// 応募条件式のモデル。
///
/// サーバ側（`private.validate_criteria`）と同じホワイトリストを持つ。
/// **クライアント側の検証はUXのためのものであり、権限の担保はサーバ側が行う**
/// （AGENTS.md R-8）。ここを緩めても安全側は崩れないが、逆に厳しくしすぎると
/// 保存できるはずの条件が作れなくなるので、必ずサーバ定義と同期させること。
library;

/// 使用できるインサイト指標。
enum CriteriaMetric {
  followers('followers', 'フォロワー数'),
  avgReach('avg_reach', '平均リーチ'),
  avgImpressions('avg_impressions', '平均インプレッション'),
  avgLikes('avg_likes', '平均いいね数'),
  avgComments('avg_comments', '平均コメント数'),
  avgSaves('avg_saves', '平均保存数'),
  avgShares('avg_shares', '平均シェア数'),
  avgViews('avg_views', '平均再生数'),
  engagementRate('engagement_rate', 'エンゲージメント率'),
  postCount('post_count', '投稿本数');

  const CriteriaMetric(this.key, this.label);

  final String key;
  final String label;

  static CriteriaMetric fromKey(String key) =>
      CriteriaMetric.values.firstWhere((CriteriaMetric m) => m.key == key);
}

/// 使用できる属性条件。
enum CriteriaAttribute {
  prefectureId('prefecture_id', '居住エリア'),
  age('age', '年齢'),
  genreId('genre_id', '興味ジャンル');

  const CriteriaAttribute(this.key, this.label);

  final String key;
  final String label;
}

enum SocialPlatform {
  instagram('instagram', 'Instagram'),
  tiktok('tiktok', 'TikTok'),
  youtube('youtube', 'YouTube');

  const SocialPlatform(this.key, this.label);

  final String key;
  final String label;
}

/// 集計期間（日）。サーバが受け付けるのは 7 / 30 / 90 のみ。
enum MetricWindow {
  d7(7, '直近7日'),
  d30(30, '直近30日'),
  d90(90, '直近90日');

  const MetricWindow(this.days, this.label);

  final int days;
  final String label;

  static MetricWindow fromDays(int days) =>
      MetricWindow.values.firstWhere((MetricWindow w) => w.days == days);
}

enum Comparator {
  gte('>=', '以上'),
  lte('<=', '以下'),
  gt('>', 'より大きい'),
  lt('<', 'より小さい'),
  eq('=', 'と等しい'),
  contains('contains', 'を含む');

  const Comparator(this.key, this.label);

  final String key;
  final String label;

  static Comparator fromKey(String key) =>
      Comparator.values.firstWhere((Comparator c) => c.key == key);
}

/// 条件式のノード。グループ（AND / OR）かリーフのいずれか。
sealed class Criteria {
  const Criteria();

  Map<String, dynamic> toJson();

  static Criteria fromJson(Map<String, dynamic> json) {
    if (json.containsKey('op')) {
      return CriteriaGroup(
        op: json['op'] == 'OR' ? LogicalOp.or : LogicalOp.and,
        children: (json['children'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => Criteria.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }
    if (json.containsKey('metric')) {
      return MetricCriteria(
        metric: CriteriaMetric.fromKey(json['metric'] as String),
        platform: SocialPlatform.values
            .firstWhere((SocialPlatform p) => p.key == json['platform']),
        window: MetricWindow.fromDays(json['window'] as int),
        comparator: Comparator.fromKey(json['cmp'] as String),
        value: (json['value'] as num).toDouble(),
      );
    }
    return AttributeCriteria(
      attribute: CriteriaAttribute.values
          .firstWhere((CriteriaAttribute a) => a.key == json['attr']),
      comparator: Comparator.fromKey(json['cmp'] as String),
      value: (json['value'] as num).toDouble(),
    );
  }

  /// ネストの深さ。サーバ側の上限は 3。
  int get depth;

  /// リーフの総数。サーバ側は 1 グループあたり 20 件まで。
  int get leafCount;
}

enum LogicalOp { and, or }

class CriteriaGroup extends Criteria {
  const CriteriaGroup({required this.op, required this.children});

  final LogicalOp op;
  final List<Criteria> children;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'op': op == LogicalOp.and ? 'AND' : 'OR',
        'children': children.map((Criteria c) => c.toJson()).toList(),
      };

  @override
  int get depth => children.isEmpty
      ? 1
      : 1 +
          children
              .map((Criteria c) => c.depth)
              .reduce((int a, int b) => a > b ? a : b);

  @override
  int get leafCount =>
      children.fold(0, (int sum, Criteria c) => sum + c.leafCount);
}

class MetricCriteria extends Criteria {
  const MetricCriteria({
    required this.metric,
    required this.platform,
    required this.window,
    required this.comparator,
    required this.value,
  });

  final CriteriaMetric metric;
  final SocialPlatform platform;
  final MetricWindow window;
  final Comparator comparator;
  final double value;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'metric': metric.key,
        'platform': platform.key,
        'window': window.days,
        'cmp': comparator.key,
        'value': value,
      };

  @override
  int get depth => 1;

  @override
  int get leafCount => 1;
}

class AttributeCriteria extends Criteria {
  const AttributeCriteria({
    required this.attribute,
    required this.comparator,
    required this.value,
  });

  final CriteriaAttribute attribute;
  final Comparator comparator;
  final double value;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'attr': attribute.key,
        'cmp': comparator.key,
        'value': value,
      };

  @override
  int get depth => 1;

  @override
  int get leafCount => 1;
}

/// 保存前のクライアント側チェック。サーバ側の検証と同じ制限。
class CriteriaValidator {
  const CriteriaValidator._();

  static const int maxDepth = 3;
  static const int maxChildren = 20;

  /// エラーがあれば表示用メッセージを返す。問題なければ null。
  static String? validate(Criteria criteria) {
    if (criteria.depth > maxDepth) {
      return '条件のグループは$maxDepth段までです。';
    }
    if (criteria is CriteriaGroup && criteria.children.length > maxChildren) {
      return '1つのグループに設定できる条件は$maxChildren件までです。';
    }
    if (criteria is CriteriaGroup) {
      for (final Criteria child in criteria.children) {
        final String? error = validate(child);
        if (error != null) {
          return error;
        }
      }
    }
    return null;
  }
}
