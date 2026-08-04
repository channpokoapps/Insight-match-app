import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/masters/master_repository.dart';
import '../domain/campaign_filter.dart';

/// 案件の絞り込み条件を編集するボトムシート。
///
/// エリア（都道府県 → 市区町村）と沿線（都道府県 → 路線 → 駅）を
/// たどれるようにして、賃貸情報サイトと同じ感覚で探せるようにする。
Future<CampaignFilter?> showCampaignFilterSheet(
  BuildContext context,
  CampaignFilter current,
) {
  return showModalBottomSheet<CampaignFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final CampaignFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late CampaignFilter _filter = widget.initial;

  /// エリア・沿線をたどるときの起点。絞り込み条件そのものではない。
  int? _areaPrefectureId;
  int? _linePrefectureId;
  int? _lineId;

  List<int> _toggled(List<int> ids, int id) {
    final List<int> next = List<int>.of(ids);
    if (next.remove(id)) {
      return next;
    }
    return next..add(id);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text('条件をしぼりこむ',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _filter = const CampaignFilter()),
                    child: const Text('クリア'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  _sectionTitle('ジャンル'),
                  _chips(
                    items: ref.watch(genresProvider),
                    selected: _filter.genreIds,
                    onTap: (int id) => setState(() => _filter = _filter
                        .copyWith(genreIds: _toggled(_filter.genreIds, id))),
                  ),
                  const Divider(height: 32),
                  _sectionTitle('エリア'),
                  // 都道府県を押すと絞り込みに加わり、同時に市区町村が開く。
                  _prefectureChips(
                    isOn: (int id) => _filter.prefectureIds.contains(id),
                    onTap: (int id) => setState(() {
                      final List<int> next = _toggled(_filter.prefectureIds, id);
                      _filter = _filter.copyWith(prefectureIds: next);
                      _areaPrefectureId = next.contains(id) ? id : null;
                    }),
                  ),
                  if (_areaPrefectureId != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _subTitle('市区町村'),
                    _chips(
                      items: ref.watch(citiesProvider(_areaPrefectureId!)),
                      selected: _filter.cityIds,
                      onTap: (int id) => setState(() => _filter = _filter
                          .copyWith(cityIds: _toggled(_filter.cityIds, id))),
                    ),
                  ],
                  const Divider(height: 32),
                  _sectionTitle('沿線・駅'),
                  // ここでの都道府県は路線をたどるための入口で、絞り込み条件には入らない。
                  _prefectureChips(
                    isOn: (int id) => _linePrefectureId == id,
                    onTap: (int id) => setState(() {
                      _linePrefectureId = _linePrefectureId == id ? null : id;
                      _lineId = null;
                    }),
                  ),
                  if (_linePrefectureId != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _subTitle('路線'),
                    _chips(
                      items:
                          ref.watch(railwayLinesProvider(_linePrefectureId!)),
                      selected: _filter.lineIds,
                      onTap: (int id) => setState(() {
                        _filter = _filter.copyWith(
                            lineIds: _toggled(_filter.lineIds, id));
                        _lineId = id;
                      }),
                    ),
                  ],
                  if (_lineId != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _subTitle('駅（路線全体でよければ選ばなくて構いません）'),
                    _chips(
                      items: ref.watch(stationsProvider(_lineId!)),
                      selected: _filter.stationIds,
                      onTap: (int id) => setState(() => _filter =
                          _filter.copyWith(
                              stationIds: _toggled(_filter.stationIds, id))),
                    ),
                  ],
                  const Divider(height: 32),
                  _sectionTitle('並び順'),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final CampaignSort s in CampaignSort.values)
                        ChoiceChip(
                          label: Text(s.label),
                          selected: _filter.sort == s,
                          onSelected: (_) =>
                              setState(() => _filter = _filter.copyWith(sort: s)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_filter),
                    child: const Text('この条件でさがす'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _subTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );

  Widget _chips({
    required AsyncValue<List<MasterItem>> items,
    required List<int> selected,
    required void Function(int) onTap,
  }) =>
      _chipsFrom(items: items, isOn: selected.contains, onTap: onTap);

  /// 都道府県の一覧。選択中か展開中のものを選択済みとして見せる。
  Widget _prefectureChips({
    required bool Function(int) isOn,
    required void Function(int) onTap,
  }) {
    return _chipsFrom(
      items: ref.watch(prefecturesProvider),
      isOn: isOn,
      onTap: onTap,
    );
  }

  Widget _chipsFrom({
    required AsyncValue<List<MasterItem>> items,
    required bool Function(int) isOn,
    required void Function(int) onTap,
  }) {
    return items.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (Object _, StackTrace __) => const Text('一覧を取得できませんでした。'),
      data: (List<MasterItem> list) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: <Widget>[
          for (final MasterItem item in list)
            FilterChip(
              label: Text(item.name),
              selected: isOn(item.id),
              onSelected: (_) => onTap(item.id),
            ),
        ],
      ),
    );
  }
}
