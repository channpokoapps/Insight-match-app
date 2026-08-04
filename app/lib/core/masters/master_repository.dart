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

  /// ジャンル一覧を表示順で返す。
  Future<List<MasterItem>> fetchGenres() =>
      _fetchList('genres', orderBy: 'sort_order');

  /// 都道府県一覧を id 順（JIS コード順）で返す。
  Future<List<MasterItem>> fetchPrefectures() =>
      _fetchList('prefectures', orderBy: 'id');

  /// 指定した都道府県の市区町村一覧を返す。
  Future<List<MasterItem>> fetchCities(int prefectureId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('cities')
          .select('id, name')
          .eq('prefecture_id', prefectureId)
          .order('id', ascending: true);
      return rows.map(MasterItem.fromJson).toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('master.cities_failed', failure.code, s);
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

  Future<List<MasterItem>> _fetchList(
    String table, {
    required String orderBy,
  }) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(table)
          .select('id, name')
          .order(orderBy, ascending: true);
      return rows.map(MasterItem.fromJson).toList();
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
