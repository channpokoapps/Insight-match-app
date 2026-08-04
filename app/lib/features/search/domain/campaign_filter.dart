/// 案件検索の絞り込み条件を持つファイル。
///
/// `FutureProvider.family` のキーになるため、値が同じなら等しいこと
/// （`==` / `hashCode`）を正しく実装する。リストの中身まで比較しないと、
/// 同じ条件で毎回リクエストが飛ぶ。
library;

import 'package:flutter/foundation.dart';

/// 案件一覧の並び順。DB 側の許可リスト（0014）と一致させること。
enum CampaignSort {
  newest('newest', '新着順'),
  rewardDesc('reward_desc', '想定価格が高い順');

  const CampaignSort(this.key, this.label);

  final String key;
  final String label;
}

/// 案件検索の絞り込み条件。
@immutable
class CampaignFilter {
  const CampaignFilter({
    this.prefectureIds = const <int>[],
    this.cityIds = const <int>[],
    this.lineIds = const <int>[],
    this.stationIds = const <int>[],
    this.genreIds = const <int>[],
    this.minReward,
    this.sort = CampaignSort.newest,
  });

  final List<int> prefectureIds;
  final List<int> cityIds;
  final List<int> lineIds;
  final List<int> stationIds;
  final List<int> genreIds;
  final int? minReward;
  final CampaignSort sort;

  /// 絞り込みが 1 つでも指定されているか。
  bool get isActive =>
      prefectureIds.isNotEmpty ||
      cityIds.isNotEmpty ||
      lineIds.isNotEmpty ||
      stationIds.isNotEmpty ||
      genreIds.isNotEmpty ||
      minReward != null;

  /// 指定中の条件の数。画面のバッジに使う。
  int get activeCount =>
      (prefectureIds.isEmpty ? 0 : 1) +
      (cityIds.isEmpty ? 0 : 1) +
      (lineIds.isEmpty ? 0 : 1) +
      (stationIds.isEmpty ? 0 : 1) +
      (genreIds.isEmpty ? 0 : 1) +
      (minReward == null ? 0 : 1);

  CampaignFilter copyWith({
    List<int>? prefectureIds,
    List<int>? cityIds,
    List<int>? lineIds,
    List<int>? stationIds,
    List<int>? genreIds,
    int? minReward,
    bool clearMinReward = false,
    CampaignSort? sort,
  }) {
    return CampaignFilter(
      prefectureIds: prefectureIds ?? this.prefectureIds,
      cityIds: cityIds ?? this.cityIds,
      lineIds: lineIds ?? this.lineIds,
      stationIds: stationIds ?? this.stationIds,
      genreIds: genreIds ?? this.genreIds,
      minReward: clearMinReward ? null : (minReward ?? this.minReward),
      sort: sort ?? this.sort,
    );
  }

  /// 空リストは「絞り込まない」を意味するため null に落として送る。
  static List<int>? toParam(List<int> ids) => ids.isEmpty ? null : ids;

  @override
  bool operator ==(Object other) =>
      other is CampaignFilter &&
      listEquals(other.prefectureIds, prefectureIds) &&
      listEquals(other.cityIds, cityIds) &&
      listEquals(other.lineIds, lineIds) &&
      listEquals(other.stationIds, stationIds) &&
      listEquals(other.genreIds, genreIds) &&
      other.minReward == minReward &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(prefectureIds),
        Object.hashAll(cityIds),
        Object.hashAll(lineIds),
        Object.hashAll(stationIds),
        Object.hashAll(genreIds),
        minReward,
        sort,
      );
}
