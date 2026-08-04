import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/masters/master_repository.dart';

/// 「その他」ジャンルの表示名。マスタ（0011_restaurant_genres.sql）と一致させる。
const String kOtherGenreName = 'その他';

/// 飲食ジャンルの複数選択。
///
/// 「その他」を選んだときだけ自由記述欄を出す。集まった記述は運営が
/// `list_genre_other_suggestions` で確認し、マスタへ昇格させる。
class GenreMultiSelect extends StatelessWidget {
  const GenreMultiSelect({
    super.key,
    required this.label,
    required this.genres,
    required this.selectedIds,
    required this.otherController,
    required this.onToggle,
    this.enabled = true,
  });

  final String label;
  final AsyncValue<List<MasterItem>> genres;
  final Set<int> selectedIds;
  final TextEditingController otherController;
  final void Function(int genreId, bool selected) onToggle;
  final bool enabled;

  /// 選択中に「その他」が含まれるか。
  static bool hasOther(List<MasterItem> genres, Set<int> selectedIds) =>
      genres.any((MasterItem g) =>
          g.name == kOtherGenreName && selectedIds.contains(g.id));

  @override
  Widget build(BuildContext context) {
    final List<MasterItem> items = genres.valueOrNull ?? <MasterItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (items.isEmpty && genres.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final MasterItem g in items)
                FilterChip(
                  label: Text(g.name),
                  selected: selectedIds.contains(g.id),
                  onSelected:
                      enabled ? (bool s) => onToggle(g.id, s) : null,
                ),
            ],
          ),
        if (hasOther(items, selectedIds)) ...<Widget>[
          const SizedBox(height: 12),
          TextField(
            controller: otherController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'その他のジャンル',
              helperText: '例: スペインバル、ビストロ など',
            ),
          ),
        ],
      ],
    );
  }
}
