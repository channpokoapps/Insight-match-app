import 'package:insight_match/core/error/app_failure.dart';
import 'package:insight_match/features/chat/domain/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFailure', () {
    test('応募条件を満たさない場合、どの条件で落ちたかを出さない', () {
      final AppFailure failure =
          AppFailure.from(Exception('応募条件を満たしていません: followers >= 5000'));
      expect(failure.kind, FailureKind.notEligible);
      expect(failure.message.contains('followers'), isFalse);
      expect(failure.message.contains('5000'), isFalse);
    });

    test('通信エラーを分類できる', () {
      final AppFailure failure =
          AppFailure.from(Exception('SocketException: failed'));
      expect(failure.kind, FailureKind.network);
    });

    test('未知の例外の内容を画面に出さない', () {
      final AppFailure failure = AppFailure.from(
          Exception('duplicate key value violates unique constraint'));
      expect(failure.kind, FailureKind.unknown);
      expect(failure.message.contains('constraint'), isFalse);
    });

    test('toString に元の例外内容を含めない', () {
      final AppFailure failure =
          AppFailure.from(Exception('secret token abc123'));
      expect(failure.toString().contains('abc123'), isFalse);
    });
  });

  group('ChatMessage', () {
    test('sender_id を含む応答を受け付けない', () {
      expect(
        () => ChatMessage.fromJson(<String, dynamic>{
          'id': '1',
          'room_id': '2',
          'sender_id': '33333333-3333-3333-3333-333333333333',
          'created_at': '2025-01-01T00:00:00Z',
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('送信者は自分か相手かだけが分かる', () {
      final ChatMessage message = ChatMessage.fromJson(<String, dynamic>{
        'id': '1',
        'room_id': '2',
        'body': 'こんにちは',
        'is_own': false,
        'sender_is_client': true,
        'counterpart_alias_no': 4,
        'created_at': '2025-01-01T00:00:00Z',
      });
      expect(message.isOwn, isFalse);
      expect(message.senderIsClient, isTrue);
      expect(message.counterpartAliasNo, 4);
      expect(message.isRead, isFalse);
    });
  });
}
