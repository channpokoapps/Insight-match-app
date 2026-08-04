import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/app_failure.dart';
import '../../core/masters/master_repository.dart';

/// 最寄り駅を選ぶボトムシート。
///
/// 駅名で直接探す経路と、都道府県 → 路線 → 駅とたどる経路の両方を用意する。
/// 路線からたどれないと「阪急千里線沿い」のような探し方ができないため。
Future<StationHit?> showStationPicker(BuildContext context) {
  return showModalBottomSheet<StationHit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => const _StationPickerSheet(),
  );
}

class _StationPickerSheet extends ConsumerStatefulWidget {
  const _StationPickerSheet();

  @override
  ConsumerState<_StationPickerSheet> createState() =>
      _StationPickerSheetState();
}

class _StationPickerSheetState extends ConsumerState<_StationPickerSheet> {
  final TextEditingController _keyword = TextEditingController();
  Timer? _debounce;
  List<StationHit> _hits = <StationHit>[];
  bool _searching = false;
  String? _error;

  int? _prefectureId;
  int? _lineId;

  @override
  void dispose() {
    _debounce?.cancel();
    _keyword.dispose();
    super.dispose();
  }

  void _onKeywordChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _hits = <StationHit>[];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String value) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final List<StationHit> hits =
          await ref.read(masterRepositoryProvider).searchStations(value);
      if (mounted) {
        setState(() => _hits = hits);
      }
    } on AppFailure catch (failure) {
      if (mounted) {
        setState(() => _error = failure.message);
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return Column(
          children: <Widget>[
            const SizedBox(height: 12),
            Text('最寄り駅を選ぶ',
                style: Theme.of(context).textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _keyword,
                onChanged: _onKeywordChanged,
                decoration: InputDecoration(
                  labelText: '駅名で探す',
                  hintText: '例: 南千里',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _keyword.text.trim().isNotEmpty
                  ? _buildSearchResults(controller)
                  : _buildDrilldown(controller),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults(ScrollController controller) {
    if (_hits.isEmpty && !_searching) {
      return const Center(child: Text('一致する駅が見つかりませんでした。'));
    }
    return ListView.builder(
      controller: controller,
      itemCount: _hits.length,
      itemBuilder: (BuildContext context, int index) {
        final StationHit hit = _hits[index];
        return ListTile(
          title: Text(hit.name),
          subtitle: Text(hit.lineName),
          onTap: () => Navigator.of(context).pop(hit),
        );
      },
    );
  }

  /// 都道府県 → 路線 → 駅。SUUMO の沿線検索と同じたどり方。
  Widget _buildDrilldown(ScrollController controller) {
    final int? prefectureId = _prefectureId;
    final int? lineId = _lineId;

    if (prefectureId == null) {
      return _MasterList(
        controller: controller,
        header: '都道府県を選ぶ',
        items: ref.watch(prefecturesProvider),
        onTap: (MasterItem item) => setState(() {
          _prefectureId = item.id;
          _lineId = null;
        }),
      );
    }
    if (lineId == null) {
      return _MasterList(
        controller: controller,
        header: '路線を選ぶ',
        items: ref.watch(railwayLinesProvider(prefectureId)),
        onBack: () => setState(() => _prefectureId = null),
        onTap: (MasterItem item) => setState(() => _lineId = item.id),
      );
    }
    return _MasterList(
      controller: controller,
      header: '駅を選ぶ',
      items: ref.watch(stationsProvider(lineId)),
      onBack: () => setState(() => _lineId = null),
      onTap: (MasterItem item) {
        final String lineName = ref
                .read(railwayLinesProvider(prefectureId))
                .valueOrNull
                ?.firstWhere(
                  (MasterItem l) => l.id == lineId,
                  orElse: () => const MasterItem(id: 0, name: ''),
                )
                .name ??
            '';
        Navigator.of(context).pop(
          StationHit(id: item.id, name: item.name, lineName: lineName),
        );
      },
    );
  }
}

class _MasterList extends StatelessWidget {
  const _MasterList({
    required this.controller,
    required this.header,
    required this.items,
    required this.onTap,
    this.onBack,
  });

  final ScrollController controller;
  final String header;
  final AsyncValue<List<MasterItem>> items;
  final void Function(MasterItem) onTap;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return items.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object _, StackTrace __) =>
          const Center(child: Text('一覧を取得できませんでした。')),
      data: (List<MasterItem> list) => ListView.builder(
        controller: controller,
        itemCount: list.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return ListTile(
              leading: onBack == null ? null : const Icon(Icons.arrow_back),
              title: Text(
                header,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              onTap: onBack,
            );
          }
          final MasterItem item = list[index - 1];
          return ListTile(
            title: Text(item.name),
            onTap: () => onTap(item),
          );
        },
      ),
    );
  }
}
