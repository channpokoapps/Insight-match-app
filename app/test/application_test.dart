import 'package:insight_match/features/application/domain/application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreatorAlias', () {
    test('連番からラベルを作る', () {
      expect(CreatorAlias.label(1), '投稿者A');
      expect(CreatorAlias.label(2), '投稿者B');
      expect(CreatorAlias.label(26), '投稿者Z');
      expect(CreatorAlias.label(27), '投稿者AA');
      expect(CreatorAlias.label(28), '投稿者AB');
      expect(CreatorAlias.label(52), '投稿者AZ');
      expect(CreatorAlias.label(53), '投稿者BA');
    });

    test('不正な連番でも識別情報を露出しない', () {
      expect(CreatorAlias.label(0), '投稿者');
      expect(CreatorAlias.label(-1), '投稿者');
    });
  });

  group('ApplicationForClient', () {
    Map<String, dynamic> validJson() => <String, dynamic>{
          'id': '11111111-1111-1111-1111-111111111111',
          'campaign_id': '22222222-2222-2222-2222-222222222222',
          'alias_no': 3,
          'status': 'matched',
          'created_at': '2025-01-01T00:00:00Z',
          'has_submission': true,
          'is_post_verified': false,
          'message': 'よろしくお願いします',
        };

    test('連番のみで投稿者を表す', () {
      final ApplicationForClient app =
          ApplicationForClient.fromJson(validJson());
      expect(app.aliasNo, 3);
      expect(app.displayName, '投稿者C');
      expect(app.status, ApplicationStatus.matched);
      expect(app.hasSubmission, isTrue);
    });

    test('識別情報が混入していたら組み立てを拒否する', () {
      for (final String key in <String>[
        'creator_id',
        'user_id',
        'display_name',
        'sns_username',
        'email',
      ]) {
        final Map<String, dynamic> json = validJson()..[key] = 'leaked';
        expect(
          () => ApplicationForClient.fromJson(json),
          throwsA(isA<StateError>()),
          reason: '$key が含まれる応答は拒否されるべき',
        );
      }
    });
  });

  group('ApplicationStatus', () {
    test('未知の値でも落ちない', () {
      expect(ApplicationStatus.fromKey('unknown_value'),
          ApplicationStatus.applied);
      expect(ApplicationStatus.fromKey(null), ApplicationStatus.applied);
    });

    test('進行中かどうかを判定できる', () {
      expect(ApplicationStatus.matched.isActive, isTrue);
      expect(ApplicationStatus.rejected.isActive, isFalse);
      expect(ApplicationStatus.completed.isActive, isFalse);
    });
  });
}
