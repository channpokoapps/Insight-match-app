import '../../search/domain/criteria.dart';

/// 保存した条件式（FR-CMP-16）。
///
/// PR依頼者が自分で作った条件の保管庫であり、インサイト実数値も
/// 投稿者の識別情報も持たない（`criteria_templates` は所有者のみ参照できる）。
class CriteriaTemplate {
  const CriteriaTemplate({
    required this.id,
    required this.name,
    required this.criteria,
    required this.createdAt,
  });

  factory CriteriaTemplate.fromJson(Map<String, dynamic> json) =>
      CriteriaTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        criteria: Criteria.fromJson(json['criteria'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String name;
  final Criteria criteria;
  final DateTime createdAt;

  /// 一覧に出す要約（例: 「条件 3 件・すべて満たす」）。
  ///
  /// 条件の中身をここで文章にすると表示のたびに書式がぶれるため、
  /// 件数と結合方法だけを示す。
  String get summary {
    if (criteria is! CriteriaGroup) {
      return '条件 1 件';
    }
    final CriteriaGroup group = criteria as CriteriaGroup;
    if (group.children.isEmpty) {
      return '条件なし';
    }
    final String op = group.op == LogicalOp.and ? 'すべて満たす' : 'いずれかを満たす';
    return '条件 ${group.leafCount} 件・$op';
  }
}
