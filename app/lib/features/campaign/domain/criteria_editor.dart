/// 条件式（AND / OR）を組み立てるための編集用ツリー（FR-CMP-04）。
///
/// `Criteria` は保存・送信用の不変モデルなので、編集途中の
/// 「まだ値が入っていないリーフ」を表現できない。ここでは編集中の
/// 未確定状態を持てる可変ノードを用意し、確定できたものだけを
/// `Criteria` へ変換する。
///
/// **条件式そのものは投稿者に返さない**（`campaigns.criteria` は
/// RPC の返却に含まれない）。ここは PR依頼者の入力補助のみを担う。
library;

import '../../search/domain/criteria.dart';

/// 編集中のノード。グループかリーフのいずれか。
sealed class CriteriaNode {
  CriteriaNode({String? id}) : id = id ?? _nextId();

  /// ウィジェットの Key に使う識別子。保存内容には含めない。
  final String id;

  static int _counter = 0;
  static String _nextId() => 'n${_counter++}';

  /// 入力が完了していれば送信用モデルを返す。未完成なら null。
  Criteria? toCriteria();

  /// このノードを根としたときのネストの深さ。
  int get depth;
}

class CriteriaNodeGroup extends CriteriaNode {
  CriteriaNodeGroup({
    this.op = LogicalOp.and,
    List<CriteriaNode>? children,
    super.id,
  }) : children = children ?? <CriteriaNode>[];

  LogicalOp op;
  final List<CriteriaNode> children;

  @override
  Criteria? toCriteria() {
    final List<Criteria> resolved = children
        .map((CriteriaNode c) => c.toCriteria())
        .whereType<Criteria>()
        .toList();
    // 空グループは「条件なし」と同じ意味になるため、親からは省く。
    if (resolved.isEmpty) {
      return null;
    }
    return CriteriaGroup(op: op, children: resolved);
  }

  @override
  int get depth => children.isEmpty
      ? 1
      : 1 +
          children
              .map((CriteriaNode c) => c.depth)
              .reduce((int a, int b) => a > b ? a : b);
}

/// インサイト指標の条件（例: Instagram の直近30日フォロワー数が1000以上）。
class CriteriaNodeMetric extends CriteriaNode {
  CriteriaNodeMetric({
    this.metric = CriteriaMetric.followers,
    this.platform = SocialPlatform.instagram,
    this.window = MetricWindow.d30,
    this.comparator = Comparator.gte,
    this.value,
    super.id,
  });

  CriteriaMetric metric;
  SocialPlatform platform;
  MetricWindow window;
  Comparator comparator;
  double? value;

  @override
  Criteria? toCriteria() => value == null
      ? null
      : MetricCriteria(
          metric: metric,
          platform: platform,
          window: window,
          comparator: comparator,
          value: value!,
        );

  @override
  int get depth => 1;
}

/// 属性の条件（居住エリア・年齢・興味ジャンル）。
class CriteriaNodeAttribute extends CriteriaNode {
  CriteriaNodeAttribute({
    this.attribute = CriteriaAttribute.age,
    this.comparator = Comparator.gte,
    this.value,
    super.id,
  });

  CriteriaAttribute attribute;
  Comparator comparator;
  double? value;

  @override
  Criteria? toCriteria() => value == null
      ? null
      : AttributeCriteria(
          attribute: attribute,
          comparator: comparator,
          value: value!,
        );

  @override
  int get depth => 1;
}

/// 編集ツリー全体の操作。
class CriteriaEditor {
  CriteriaEditor({CriteriaNodeGroup? root})
      : root = root ?? CriteriaNodeGroup();

  /// 保存済みの条件式から編集ツリーを復元する。
  factory CriteriaEditor.fromCriteria(Criteria? criteria) {
    if (criteria == null) {
      return CriteriaEditor();
    }
    final CriteriaNode node = _toNode(criteria);
    return CriteriaEditor(
      root: node is CriteriaNodeGroup
          ? node
          : CriteriaNodeGroup(children: <CriteriaNode>[node]),
    );
  }

  final CriteriaNodeGroup root;

  static CriteriaNode _toNode(Criteria criteria) => switch (criteria) {
        CriteriaGroup(:final LogicalOp op, :final List<Criteria> children) =>
          CriteriaNodeGroup(
            op: op,
            children: children.map(_toNode).toList(),
          ),
        MetricCriteria(
          :final CriteriaMetric metric,
          :final SocialPlatform platform,
          :final MetricWindow window,
          :final Comparator comparator,
          :final double value,
        ) =>
          CriteriaNodeMetric(
            metric: metric,
            platform: platform,
            window: window,
            comparator: comparator,
            value: value,
          ),
        AttributeCriteria(
          :final CriteriaAttribute attribute,
          :final Comparator comparator,
          :final double value,
        ) =>
          CriteriaNodeAttribute(
            attribute: attribute,
            comparator: comparator,
            value: value,
          ),
      };

  /// 送信用の条件式。1 件も条件が無ければ「条件なし」を表す空グループ。
  Criteria toCriteria() =>
      root.toCriteria() ??
      const CriteriaGroup(op: LogicalOp.and, children: <Criteria>[]);

  /// 入力が完了しているリーフの数。
  int get completedLeafCount => _countCompleted(root);

  /// 値が未入力のリーフがあるか。あるうちは該当人数を問い合わせない。
  bool get hasIncompleteLeaf => _hasIncomplete(root);

  /// これ以上グループを入れ子にできるか（サーバ側の上限は 3 段）。
  bool canNestUnder(CriteriaNodeGroup group) =>
      _depthOf(root, group, 1) + 1 <= CriteriaValidator.maxDepth;

  /// 保存前の検証。問題があれば表示用メッセージを返す。
  String? validate() {
    if (root.depth > CriteriaValidator.maxDepth) {
      return '条件のグループは${CriteriaValidator.maxDepth}段までです。';
    }
    if (hasIncompleteLeaf) {
      return '値が入力されていない条件があります。入力するか、条件を削除してください。';
    }
    return CriteriaValidator.validate(toCriteria());
  }

  /// 親を辿って [target] を削除する。見つからなければ何もしない。
  void remove(CriteriaNode target) => _remove(root, target);

  static bool _remove(CriteriaNodeGroup parent, CriteriaNode target) {
    if (parent.children.remove(target)) {
      return true;
    }
    for (final CriteriaNode child in parent.children) {
      if (child is CriteriaNodeGroup && _remove(child, target)) {
        return true;
      }
    }
    return false;
  }

  static int _countCompleted(CriteriaNode node) => switch (node) {
        CriteriaNodeGroup(:final List<CriteriaNode> children) =>
          children.fold(0, (int s, CriteriaNode c) => s + _countCompleted(c)),
        CriteriaNodeMetric(:final double? value) => value == null ? 0 : 1,
        CriteriaNodeAttribute(:final double? value) => value == null ? 0 : 1,
      };

  static bool _hasIncomplete(CriteriaNode node) => switch (node) {
        CriteriaNodeGroup(:final List<CriteriaNode> children) =>
          children.any(_hasIncomplete),
        CriteriaNodeMetric(:final double? value) => value == null,
        CriteriaNodeAttribute(:final double? value) => value == null,
      };

  /// [target] が根から何段目にあるかを返す。見つからなければ 0。
  static int _depthOf(CriteriaNodeGroup node, CriteriaNodeGroup target,
      int currentDepth) {
    if (identical(node, target)) {
      return currentDepth;
    }
    for (final CriteriaNode child in node.children) {
      if (child is CriteriaNodeGroup) {
        final int found = _depthOf(child, target, currentDepth + 1);
        if (found > 0) {
          return found;
        }
      }
    }
    return 0;
  }
}
