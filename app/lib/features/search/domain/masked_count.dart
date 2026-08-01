/// k-匿名性で丸められた件数。
///
/// **サーバは 5 人未満のとき実数を返さない。**
/// クライアント側で「masked のときは推測値を出す」といった補完を絶対に行わないこと。
class MaskedCount {
  const MaskedCount({
    required this.count,
    required this.masked,
    required this.label,
  });

  factory MaskedCount.fromJson(Map<String, dynamic> json) => MaskedCount(
        count: json['count'] as int?,
        masked: json['masked'] as bool? ?? true,
        label: json['label'] as String? ?? '取得できません',
      );

  /// 丸められている場合は null。
  final int? count;

  final bool masked;

  /// 画面にそのまま表示してよい文言（例：「23人」「5人未満」）。
  final String label;

  /// 定員に足りているかの判断は、丸められている場合は行えない。
  bool get isDeterminable => !masked && count != null;
}
