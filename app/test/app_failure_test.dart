import 'package:insight_match/core/error/app_failure.dart';
import 'package:insight_match/features/chat/domain/message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    test('列が無い応答をサーバー未更新として案内する', () {
      // 本番 DB にマイグレーションが未反映のときに来る応答
      // （案件作成画面が開けなくなっていた原因）。
      final AppFailure failure = AppFailure.from(
        const PostgrestException(
          message: 'column client_profiles.genre_ids does not exist',
          code: '42703',
        ),
      );
      expect(failure.kind, FailureKind.serverOutdated);
      expect(failure.message.contains('genre_ids'), isFalse);
      expect(failure.message.contains('反映'), isTrue);
    });

    test('スキーマキャッシュに無い関数もサーバー未更新として扱う', () {
      final AppFailure failure = AppFailure.from(
        const PostgrestException(
          message: 'Could not find the function public.count_matching_creators',
          code: 'PGRST202',
        ),
      );
      expect(failure.kind, FailureKind.serverOutdated);
    });

    test('変換済みの AppFailure を unknown に潰さない', () {
      const AppFailure original =
          AppFailure(FailureKind.conflict, 'すでに公開済みです。');
      expect(AppFailure.from(original), same(original));
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
