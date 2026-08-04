import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:insight_match/core/address/postal_code_repository.dart';
import 'package:insight_match/core/error/app_failure.dart';

PostalCodeRepository _repo(http.Client client) => PostalCodeRepository(
      httpClient: client,
      apiBase: 'https://example.test/search',
    );

String _body(Object? results) => jsonEncode(<String, dynamic>{
      'status': 200,
      'results': results,
    });

const List<Map<String, String>> _umeda = <Map<String, String>>[
  <String, String>{
    'address1': '大阪府',
    'address2': '大阪市北区',
    'address3': '梅田',
  },
];

void main() {
  group('normalizePostalCode', () {
    test('ハイフンや空白を落として数字だけにする', () {
      expect(normalizePostalCode('150-0002'), '1500002');
      expect(normalizePostalCode(' 150 0002 '), '1500002');
    });

    test('全角数字も受け付ける', () {
      expect(normalizePostalCode('１５００００２'), '1500002');
    });

    test('数字以外しかなければ空になる', () {
      expect(normalizePostalCode('あいうえお'), '');
    });
  });

  group('PostalCodeRepository.lookup', () {
    test('都道府県・市区町村・町域を取り出す', () async {
      final MockClient client = MockClient(
        (http.Request _) async => http.Response(
          _body(_umeda),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );
      final PostalAddress? address = await _repo(client).lookup('5300001');
      expect(address, isNotNull);
      expect(address!.prefectureName, '大阪府');
      expect(address.cityName, '大阪市北区');
      expect(address.townName, '梅田');
    });

    test('7 桁でなければ問い合わせない', () async {
      bool called = false;
      final MockClient client = MockClient((http.Request _) async {
        called = true;
        return http.Response(_body(null), 200);
      });
      expect(await _repo(client).lookup('150'), isNull);
      expect(called, isFalse);
    });

    test('該当なしの応答は null を返す（例外にしない）', () async {
      final MockClient client = MockClient(
        (http.Request _) async => http.Response(_body(null), 200),
      );
      expect(await _repo(client).lookup('9999999'), isNull);
    });

    test('通信に失敗したら AppFailure を投げる', () async {
      final MockClient client = MockClient(
        (http.Request _) async => http.Response('{}', 500),
      );
      await expectLater(
        _repo(client).lookup('1500002'),
        throwsA(isA<AppFailure>()),
      );
    });

    test('例外の中身を画面向けメッセージに漏らさない', () async {
      final MockClient client = MockClient(
        (http.Request _) async => throw Exception('internal token abc123'),
      );
      try {
        await _repo(client).lookup('1500002');
        fail('例外が投げられていない');
      } on AppFailure catch (failure) {
        expect(failure.message, isNot(contains('abc123')));
      }
    });

    test('郵便番号は数字だけにしてから問い合わせる', () async {
      String? requested;
      final MockClient client = MockClient((http.Request req) async {
        requested = req.url.queryParameters['zipcode'];
        return http.Response(_body(null), 200);
      });
      await _repo(client).lookup('150-0002');
      expect(requested, '1500002');
    });
  });
}
