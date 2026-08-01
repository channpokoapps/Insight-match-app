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
