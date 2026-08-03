import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/auth/domain/auth_validators.dart';

void main() {
  group('isValidEmail', () {
    test('一般的な形式を受け付ける', () {
      expect(isValidEmail('user@example.com'), isTrue);
      expect(isValidEmail(' user@example.co.jp '), isTrue);
    });

    test('明らかな誤入力を弾く', () {
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail('user'), isFalse);
      expect(isValidEmail('user@'), isFalse);
      expect(isValidEmail('user@example'), isFalse);
      expect(isValidEmail('us er@example.com'), isFalse);
      expect(isValidEmail('user@@example.com'), isFalse);
    });
  });

  group('validatePassword', () {
    test('8 文字以上・英数字混在なら通る', () {
      expect(validatePassword('abcd1234'), isNull);
    });

    test('短いパスワードは弾く', () {
      expect(validatePassword('ab12'), isNotNull);
    });

    test('英字のみ・数字のみは弾く', () {
      expect(validatePassword('abcdefgh'), isNotNull);
      expect(validatePassword('12345678'), isNotNull);
    });
  });

  group('年齢確認（OI-08）', () {
    final DateTime now = DateTime(2026, 8, 2);

    test('18 歳の誕生日当日は登録できる', () {
      expect(isOldEnough(DateTime(2008, 8, 2), now), isTrue);
    });

    test('18 歳未満は登録できない', () {
      expect(isOldEnough(DateTime(2008, 8, 3), now), isFalse);
    });
  });
}
