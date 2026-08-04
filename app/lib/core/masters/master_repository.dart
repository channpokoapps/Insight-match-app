/// マスタデータ（ジャンル・都道府県・市区町村・駅）の取得をまとめるファイル。
///
/// 全ログインユーザーが SELECT できる読み取り専用データ
/// （`0004_rls_policies.sql` の `*_select_all` ポリシー）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/app_failure.dart';
import '../logging/app_logger.dart';
import '../supabase/supabase_providers.dart';

/// id と表示名のみを持つマスタ項目。
class MasterItem {
  const MasterItem({required this.id, required this.name});

  factory MasterItem.fromJson(Map<String, dynamic> json) =>
      MasterItem(id: json['id'] as int, name: json['name'] as String);

  final int id;
  final String name;
}

/// 駅の検索結果。同名の駅が複数の路線にあるため、路線名を添えて区別する。
class StationHit {
  const StationHit({
    required this.id,
    required this.name,
    required this.lineName,
  });

  final int id;
  final String name;
  final String lineName;

  /// 「阪急千里線 南千里」のような表示用ラベル。
  String get label => lineName.isEmpty ? name : '$lineName $name';
}

/// 住所名から突き合わせたエリアの id。突き合わなければ null。
class ResolvedArea {
  const ResolvedArea({this.prefectureId, this.cityId});

  final int? prefectureId;
  final int? cityId;
}

/// マスタデータの取得リポジトリ。
class MasterRepository {
  const MasterRepository(this._client);

  final SupabaseClient _client;

  /// 1 リクエストで取得する件数。`supabase/config.toml` の `max_rows` と揃える。
  static const int _pageSize = 100;

  /// ジャンル一覧を表示順で返す。
  Future<List<MasterItem>> fetchGenres() =>
      _fetchList('genres', orderBy: 'sort_order');

  /// 都道府県一覧を id 順（JIS コード順）で返す。
  Future<List<MasterItem>> fetchPrefectures() =>
      _fetchList('prefectures', orderBy: 'id');

  /// 指定した都道府県の市区町村一覧を返す。
  ///
  /// 北海道は 194 件あり `max_rows` の 1 ページに収まらないため、
  /// [_fetchList] のページングで全件を取り切る。
  Future<List<MasterItem>> fetchCities(int prefectureId) => _fetchList(
        'cities',
        orderBy: 'id',
        filter: (PostgrestFilterBuilder<List<Map<String, dynamic>>> query) =>
            query.eq('prefecture_id', prefectureId),
      );

  /// 指定した都道府県を通る路線の一覧を返す。
  ///
  /// 全国には同名の路線があるため、表示名には事業者を区別できる情報を
  /// 付けずに済むよう、都道府県で絞り込んでから見せる想定。
  Future<List<MasterItem>> fetchRailwayLines(int prefectureId) => _fetchList(
        'railway_lines',
        orderBy: 'id',
        filter: (PostgrestFilterBuilder<List<Map<String, dynamic>>> query) =>
            query.contains('prefecture_ids', <int>[prefectureId]),
      );

  /// 指定した路線の駅を、路線の並び順で返す。
  Future<List<MasterItem>> fetchStations(int lineId) => _fetchList(
        'stations',
        orderBy: 'id',
        filter: (PostgrestFilterBuilder<List<Map<String, dynamic>>> query) =>
            query.eq('line_id', lineId),
      );

  /// 駅名の部分一致で駅を探す。路線名を添えて返す。
  Future<List<StationHit>> searchStations(String query) async {
    final String keyword = query.trim();
    if (keyword.isEmpty) {
      return <StationHit>[];
    }
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('stations')
          .select('id, name, railway_lines!inner(name)')
          .ilike('name', '%$keyword%')
          .limit(50);
      return rows
          .map((Map<String, dynamic> row) => StationHit(
                id: row['id'] as int,
                name: row['name'] as String,
                lineName:
                    (row['railway_lines'] as Map<String, dynamic>?)?['name']
                            as String? ??
                        '',
              ))
          .toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('master.station_search_failed', failure.code, s);
      throw failure;
    }
  }

  /// 駅 id から「路線名 / 駅名」の表示用ラベルを引く。
  Future<StationHit?> fetchStation(int stationId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('stations')
          .select('id, name, railway_lines!inner(name)')
          .eq('id', stationId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return StationHit(
        id: row['id'] as int,
        name: row['name'] as String,
        lineName: (row['railway_lines'] as Map<String, dynamic>?)?['name']
                as String? ??
            '',
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('master.station_fetch_failed', failure.code, s);
      throw failure;
    }
  }

  /// 住所の名前（都道府県名・市区町村名）をマスタの id に突き合わせる。
  ///
  /// 郵便番号検索の結果を画面の選択状態へ反映するために使う。
  /// 突き合わなければ null を返す（表記ゆれで一致しないことがあるため、
  /// 例外にはせず手入力に任せる）。
  Future<ResolvedArea> resolveArea({
    required String prefectureName,
    String cityName = '',
  }) async {
    try {
      final Map<String, dynamic>? prefecture = await _client
          .from('prefectures')
          .select('id')
          .eq('name', prefectureName)
          .maybeSingle();
      final int? prefectureId = prefecture?['id'] as int?;
      if (prefectureId == null || cityName.isEmpty) {
        return ResolvedArea(prefectureId: prefectureId);
      }
      final Map<String, dynamic>? city = await _client
          .from('cities')
          .select('id')
          .eq('prefecture_id', prefectureId)
          .eq('name', cityName)
          .maybeSingle();
      return ResolvedArea(
        prefectureId: prefectureId,
        cityId: city?['id'] as int?,
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('master.resolve_area_failed', failure.code, s);
      throw failure;
    }
  }

  /// マスタを全件取得する。
  ///
  /// PostgREST は `supabase/config.toml` の `max_rows`（100）で応答を打ち切る。
  /// 打ち切りはエラーにならず**黙って件数が減る**ため、最終ページ
  /// （取得件数がページサイズ未満）に達するまで `range` を繰り返す。
  /// 1 ページで収まるマスタ（ジャンル・都道府県など）は 1 往復で終わる。
  Future<List<MasterItem>> _fetchList(
    String table, {
    required String orderBy,
    PostgrestFilterBuilder<List<Map<String, dynamic>>> Function(
      PostgrestFilterBuilder<List<Map<String, dynamic>>> query,
    )? filter,
  }) async {
    try {
      final List<MasterItem> items = <MasterItem>[];
      for (int offset = 0;; offset += _pageSize) {
        PostgrestFilterBuilder<List<Map<String, dynamic>>> query =
            _client.from(table).select('id, name');
        if (filter != null) {
          query = filter(query);
        }
        // id を第 2 キーにして、並び順に同値があってもページ境界で
        // 行が重複・欠落しないようにする（genres の sort_order など）。
        final List<Map<String, dynamic>> rows = await query
            .order(orderBy, ascending: true)
            .order('id', ascending: true)
            .range(offset, offset + _pageSize - 1);
        items.addAll(rows.map(MasterItem.fromJson));
        if (rows.length < _pageSize) {
          return items;
        }
      }
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('master.${table}_failed', failure.code, s);
      throw failure;
    }
  }
}

final Provider<MasterRepository> masterRepositoryProvider =
    Provider<MasterRepository>(
  (Ref ref) => MasterRepository(ref.watch(supabaseClientProvider)),
);

/// ジャンル一覧。アプリ起動中はキャッシュされる。
final FutureProvider<List<MasterItem>> genresProvider =
    FutureProvider<List<MasterItem>>(
  (Ref ref) => ref.watch(masterRepositoryProvider).fetchGenres(),
);

/// 都道府県一覧。アプリ起動中はキャッシュされる。
final FutureProvider<List<MasterItem>> prefecturesProvider =
    FutureProvider<List<MasterItem>>(
  (Ref ref) => ref.watch(masterRepositoryProvider).fetchPrefectures(),
);

/// 都道府県別の市区町村一覧。
final FutureProviderFamily<List<MasterItem>, int> citiesProvider =
    FutureProvider.family<List<MasterItem>, int>(
  (Ref ref, int prefectureId) =>
      ref.watch(masterRepositoryProvider).fetchCities(prefectureId),
);

/// 都道府県別の路線一覧。
final FutureProviderFamily<List<MasterItem>, int> railwayLinesProvider =
    FutureProvider.family<List<MasterItem>, int>(
  (Ref ref, int prefectureId) =>
      ref.watch(masterRepositoryProvider).fetchRailwayLines(prefectureId),
);

/// 路線別の駅一覧。
final FutureProviderFamily<List<MasterItem>, int> stationsProvider =
    FutureProvider.family<List<MasterItem>, int>(
  (Ref ref, int lineId) =>
      ref.watch(masterRepositoryProvider).fetchStations(lineId),
);
