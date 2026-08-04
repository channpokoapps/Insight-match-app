/// 郵便番号から住所を引くファイル。
///
/// 日本郵便の住所データは自前で持たず、外部 API に問い合わせる。
/// ここが返すのは住所の**名前**だけで、マスタの id への突き合わせは
/// `MasterRepository.resolveArea` が行う（Supabase を触るのはあちら側）。
///
/// API が落ちていても店舗登録が止まらないよう、呼び出し側は失敗しても
/// 手入力を続けられるようにすること。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../error/app_failure.dart';
import '../logging/app_logger.dart';

/// 郵便番号 1 件ぶんの住所（名前のみ）。
class PostalAddress {
  const PostalAddress({
    required this.prefectureName,
    required this.cityName,
    required this.townName,
  });

  /// 都道府県名（例: 大阪府）。
  final String prefectureName;

  /// 市区町村名（例: 大阪市北区）。
  final String cityName;

  /// 町域名（例: 梅田）。住所欄の初期値に使う。
  final String townName;
}

/// 郵便番号から住所を引くリポジトリ。
class PostalCodeRepository {
  const PostalCodeRepository({
    required http.Client httpClient,
    required String apiBase,
  })  : _http = httpClient,
        _apiBase = apiBase;

  final http.Client _http;
  final String _apiBase;

  /// 7 桁の郵便番号から住所を引く。7 桁でない・該当なしのときは null。
  ///
  /// [postalCode] はハイフン付きでもよい（数字以外は除去する）。
  Future<PostalAddress?> lookup(String postalCode) async {
    final String digits = normalizePostalCode(postalCode);
    if (digits.length != 7) {
      return null;
    }
    try {
      final http.Response res = await _http
          .get(Uri.parse('$_apiBase?zipcode=$digits'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw http.ClientException('status ${res.statusCode}');
      }
      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final List<dynamic>? results = body['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        return null;
      }
      final Map<String, dynamic> first = results.first as Map<String, dynamic>;
      final String prefectureName = (first['address1'] as String?) ?? '';
      if (prefectureName.isEmpty) {
        return null;
      }
      return PostalAddress(
        prefectureName: prefectureName,
        cityName: (first['address2'] as String?) ?? '',
        townName: (first['address3'] as String?) ?? '',
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('postal.lookup_failed', failure.code, s);
      throw failure;
    }
  }
}

/// 郵便番号から数字だけを取り出す。全角数字も受け付ける。
String normalizePostalCode(String input) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in input.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buffer.writeCharCode(rune);
    } else if (rune >= 0xFF10 && rune <= 0xFF19) {
      // 全角数字 ０-９
      buffer.writeCharCode(rune - 0xFF10 + 0x30);
    }
  }
  return buffer.toString();
}

final Provider<http.Client> httpClientProvider =
    Provider<http.Client>((Ref ref) {
  final http.Client client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final Provider<PostalCodeRepository> postalCodeRepositoryProvider =
    Provider<PostalCodeRepository>(
  (Ref ref) => PostalCodeRepository(
    httpClient: ref.watch(httpClientProvider),
    apiBase: ref.watch(appConfigProvider).postalCodeApiBase,
  ),
);
