import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async/debounce.dart';
import '../../../core/masters/master_repository.dart';
import '../../search/domain/criteria.dart';
import '../../search/domain/masked_count.dart';
import '../data/client_campaign_repository.dart';
import '../domain/criteria_editor.dart';

/// 条件に一致する投稿者数（FR-CMP-05 / T-114）。
///
/// 条件を変えるたびに呼ばれるため、入力が落ち着くまで待ってから問い合わせる。
/// キーは条件式の JSON 文字列。同じ条件ならキャッシュが効く。
final AutoDisposeFutureProviderFamily<MaskedCount, String>
    matchingCreatorCountProvider =
    FutureProvider.autoDispose.family<MaskedCount, String>(
  (Ref ref, String criteriaJson) async {
    await debounce(ref, const Duration(milliseconds: 500));
    final Criteria criteria =
        Criteria.fromJson(jsonDecode(criteriaJson) as Map<String, dynamic>);
    return ref.read(clientCampaignRepositoryProvider).countMatching(criteria);
  },
);

/// AND / OR の条件式ビルダー（FR-CMP-04 / T-113）。
///
/// 編集ツリーは呼び出し側が保持する。ここは表示と操作だけを行い、
/// 変更があれば [onChanged] で知らせる。
class CriteriaBuilder extends StatelessWidget {
  const CriteriaBuilder({
    required this.editor,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final CriteriaEditor editor;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _GroupCard(
      group: editor.root,
      editor: editor,
      onChanged: onChanged,
      enabled: enabled,
      isRoot: true,
    );
  }
}

/// 該当人数の表示（FR-CMP-05）。
///
/// **k 未満のときサーバは実数を返さない。** ここでも推定値を出さず、
/// サーバが返した文言をそのまま見せる。
class MatchingCountBadge extends ConsumerWidget {
  const MatchingCountBadge({required this.editor, super.key});

  final CriteriaEditor editor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    if (editor.hasIncompleteLeaf) {
      return _Frame(
        icon: Icons.edit_outlined,
        color: Colors.grey.shade600,
        text: '値を入力すると、条件に合う投稿者の人数を表示します',
      );
    }
    final AsyncValue<MaskedCount> count = ref.watch(
      matchingCreatorCountProvider(jsonEncode(editor.toCriteria().toJson())),
    );
    return count.when(
      loading: () => _Frame(
        icon: Icons.hourglass_empty,
        color: Colors.grey.shade600,
        text: '条件に合う投稿者を数えています…',
      ),
      error: (Object e, StackTrace _) => _Frame(
        icon: Icons.error_outline,
        color: theme.colorScheme.error,
        text: '該当人数を取得できませんでした。時間をおいて条件を変更してください。',
      ),
      data: (MaskedCount value) => _Frame(
        icon: Icons.groups_outlined,
        color: theme.colorScheme.primary,
        text: '条件に合う投稿者：${value.label}',
        // 丸められている＝これ以上絞ると誰にも届かない可能性がある、という
        // 運用上の警告。実数の推測につながる補足は出さない。
        note: value.masked ? '人数が少ないため、正確な人数は表示していません。' : null,
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.icon,
    required this.color,
    required this.text,
    this.note,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              note!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.editor,
    required this.onChanged,
    required this.enabled,
    this.isRoot = false,
  });

  final CriteriaNodeGroup group;
  final CriteriaEditor editor;
  final VoidCallback onChanged;
  final bool enabled;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SegmentedButton<LogicalOp>(
                segments: const <ButtonSegment<LogicalOp>>[
                  ButtonSegment<LogicalOp>(
                    value: LogicalOp.and,
                    label: Text('すべて満たす'),
                  ),
                  ButtonSegment<LogicalOp>(
                    value: LogicalOp.or,
                    label: Text('いずれか'),
                  ),
                ],
                selected: <LogicalOp>{group.op},
                showSelectedIcon: false,
                onSelectionChanged: enabled
                    ? (Set<LogicalOp> selected) {
                        group.op = selected.first;
                        onChanged();
                      }
                    : null,
              ),
              const Spacer(),
              if (!isRoot)
                IconButton(
                  tooltip: 'このグループを削除',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: enabled
                      ? () {
                          editor.remove(group);
                          onChanged();
                        }
                      : null,
                ),
            ],
          ),
          if (group.children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                isRoot ? '条件を追加しないと、すべての投稿者が応募できます。' : '条件を追加してください。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ),
          for (final CriteriaNode child in group.children)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: switch (child) {
                CriteriaNodeGroup() => _GroupCard(
                    group: child,
                    editor: editor,
                    onChanged: onChanged,
                    enabled: enabled,
                  ),
                CriteriaNodeMetric() => _MetricRow(
                    node: child,
                    editor: editor,
                    onChanged: onChanged,
                    enabled: enabled,
                  ),
                CriteriaNodeAttribute() => _AttributeRow(
                    node: child,
                    editor: editor,
                    onChanged: onChanged,
                    enabled: enabled,
                  ),
              },
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: <Widget>[
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('インサイト条件'),
                onPressed: enabled
                    ? () {
                        group.children.add(CriteriaNodeMetric());
                        onChanged();
                      }
                    : null,
              ),
              TextButton.icon(
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('属性条件'),
                onPressed: enabled
                    ? () {
                        group.children.add(CriteriaNodeAttribute());
                        onChanged();
                      }
                    : null,
              ),
              if (editor.canNestUnder(group))
                TextButton.icon(
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('グループ'),
                  onPressed: enabled
                      ? () {
                          group.children.add(CriteriaNodeGroup());
                          onChanged();
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.node,
    required this.editor,
    required this.onChanged,
    required this.enabled,
  });

  final CriteriaNodeMetric node;
  final CriteriaEditor editor;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _LeafFrame(
      onRemove: enabled
          ? () {
              editor.remove(node);
              onChanged();
            }
          : null,
      children: <Widget>[
        _Dropdown<SocialPlatform>(
          label: 'SNS',
          value: node.platform,
          items: SocialPlatform.values,
          labelOf: (SocialPlatform v) => v.label,
          enabled: enabled,
          onChanged: (SocialPlatform v) {
            node.platform = v;
            onChanged();
          },
        ),
        _Dropdown<CriteriaMetric>(
          label: '指標',
          value: node.metric,
          items: CriteriaMetric.values,
          labelOf: (CriteriaMetric v) => v.label,
          enabled: enabled,
          onChanged: (CriteriaMetric v) {
            node.metric = v;
            onChanged();
          },
        ),
        _Dropdown<MetricWindow>(
          label: '期間',
          value: node.window,
          items: MetricWindow.values,
          labelOf: (MetricWindow v) => v.label,
          enabled: enabled,
          onChanged: (MetricWindow v) {
            node.window = v;
            onChanged();
          },
        ),
        _ValueField(
          initial: node.value,
          enabled: enabled,
          onChanged: (double? v) {
            node.value = v;
            onChanged();
          },
        ),
        _Dropdown<Comparator>(
          label: '条件',
          value: node.comparator,
          items: _numericComparators,
          labelOf: (Comparator v) => v.label,
          enabled: enabled,
          onChanged: (Comparator v) {
            node.comparator = v;
            onChanged();
          },
        ),
      ],
    );
  }
}

class _AttributeRow extends ConsumerWidget {
  const _AttributeRow({
    required this.node,
    required this.editor,
    required this.onChanged,
    required this.enabled,
  });

  final CriteriaNodeAttribute node;
  final CriteriaEditor editor;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<MasterItem> prefectures =
        ref.watch(prefecturesProvider).valueOrNull ?? <MasterItem>[];
    final List<MasterItem> genres =
        ref.watch(genresProvider).valueOrNull ?? <MasterItem>[];
    return _LeafFrame(
      onRemove: enabled
          ? () {
              editor.remove(node);
              onChanged();
            }
          : null,
      children: <Widget>[
        _Dropdown<CriteriaAttribute>(
          label: '属性',
          value: node.attribute,
          items: CriteriaAttribute.values,
          labelOf: (CriteriaAttribute v) => v.label,
          enabled: enabled,
          onChanged: (CriteriaAttribute v) {
            node.attribute = v;
            // 属性ごとに値の意味が変わるため、選び直しを促して値を消す。
            node.value = null;
            node.comparator =
                v == CriteriaAttribute.age ? Comparator.gte : Comparator.eq;
            onChanged();
          },
        ),
        if (node.attribute == CriteriaAttribute.age) ...<Widget>[
          _ValueField(
            initial: node.value,
            enabled: enabled,
            suffix: '歳',
            onChanged: (double? v) {
              node.value = v;
              onChanged();
            },
          ),
          _Dropdown<Comparator>(
            label: '条件',
            value: node.comparator,
            items: _numericComparators,
            labelOf: (Comparator v) => v.label,
            enabled: enabled,
            onChanged: (Comparator v) {
              node.comparator = v;
              onChanged();
            },
          ),
        ] else
          _Dropdown<int>(
            label: node.attribute == CriteriaAttribute.prefectureId
                ? '都道府県'
                : 'ジャンル',
            value: node.value?.toInt(),
            items: <int>[
              for (final MasterItem m
                  in node.attribute == CriteriaAttribute.prefectureId
                      ? prefectures
                      : genres)
                m.id,
            ],
            labelOf: (int id) =>
                (node.attribute == CriteriaAttribute.prefectureId
                        ? prefectures
                        : genres)
                    .firstWhere(
                      (MasterItem m) => m.id == id,
                      orElse: () => MasterItem(id: id, name: '#$id'),
                    )
                    .name,
            enabled: enabled,
            onChanged: (int v) {
              node.value = v.toDouble();
              node.comparator = Comparator.eq;
              onChanged();
            },
          ),
      ],
    );
  }
}

/// 数値に使える比較演算子。`contains` は数値条件では意味を持たないため外す。
const List<Comparator> _numericComparators = <Comparator>[
  Comparator.gte,
  Comparator.lte,
  Comparator.gt,
  Comparator.lt,
  Comparator.eq,
];

class _LeafFrame extends StatelessWidget {
  const _LeafFrame({required this.children, required this.onRemove});

  final List<Widget> children;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ),
          IconButton(
            tooltip: 'この条件を削除',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final bool enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<T>(
        key: ValueKey<String>('$label-$value'),
        initialValue: items.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<T>>[
          for (final T item in items)
            DropdownMenuItem<T>(
              value: item,
              child: Text(labelOf(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: enabled
            ? (T? v) {
                if (v != null) {
                  onChanged(v);
                }
              }
            : null,
      ),
    );
  }
}

class _ValueField extends StatefulWidget {
  const _ValueField({
    required this.initial,
    required this.enabled,
    required this.onChanged,
    this.suffix,
  });

  final double? initial;
  final bool enabled;
  final String? suffix;
  final ValueChanged<double?> onChanged;

  @override
  State<_ValueField> createState() => _ValueFieldState();
}

class _ValueFieldState extends State<_ValueField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null ? '' : _format(widget.initial!),
  );

  static String _format(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          labelText: '値',
          isDense: true,
          suffixText: widget.suffix,
          border: const OutlineInputBorder(),
        ),
        onChanged: (String text) =>
            widget.onChanged(double.tryParse(text.trim())),
      ),
    );
  }
}
