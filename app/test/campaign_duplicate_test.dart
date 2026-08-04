import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/campaign/domain/campaign_draft.dart';
import 'package:insight_match/features/campaign/domain/client_campaign.dart';
import 'package:insight_match/features/campaign/domain/criteria_template.dart';
import 'package:insight_match/features/search/domain/criteria.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 4, 10, 30);

  CampaignDraft draft({
    required DateTime applyEnd,
    required DateTime visitStart,
    required DateTime visitEnd,
    required DateTime postStart,
    required DateTime postEnd,
    String title = '過去の案件',
    Criteria? criteria,
  }) =>
      CampaignDraft(
        title: title,
        storeName: 'テストカフェ',
        platforms: <CampaignPlatform>{CampaignPlatform.instagram},
        rewardDescription: 'ランチ 1名分',
        rewardValueJpy: 1200,
        quota: 2,
        applyEndDate: applyEnd,
        visitStartDate: visitStart,
        visitEndDate: visitEnd,
        postStartDate: postStart,
        postEndDate: postEnd,
        requiredContent: '写真3枚以上',
        criteria: criteria,
        hashtags: const <String>['#カフェ巡り'],
      );

  group('CampaignDraft.asDuplicate', () {
    test('締切が過ぎた案件は期間の長さを保ったままずらす', () {
      // 締切が 30 日前 → 締切が「今日の 1 週間後」になるよう全体を +37 日。
      final CampaignDraft source = draft(
        applyEnd: DateTime(2026, 7, 5),
        visitStart: DateTime(2026, 7, 6),
        visitEnd: DateTime(2026, 7, 12),
        postStart: DateTime(2026, 7, 6),
        postEnd: DateTime(2026, 7, 19),
      );
      final CampaignDraft copy = source.asDuplicate(now: now);

      expect(copy.applyEndDate, DateTime(2026, 8, 11));
      expect(copy.visitStartDate, DateTime(2026, 8, 12));
      expect(copy.visitEndDate, DateTime(2026, 8, 18));
      expect(copy.postStartDate, DateTime(2026, 8, 12));
      expect(copy.postEndDate, DateTime(2026, 8, 25));
      // 期間の長さは変わらない
      expect(
        copy.postEndDate.difference(copy.applyEndDate),
        source.postEndDate.difference(source.applyEndDate),
      );
    });

    test('ずらした複製はそのまま保存できる', () {
      final CampaignDraft copy = draft(
        applyEnd: DateTime(2026, 7, 5),
        visitStart: DateTime(2026, 7, 6),
        visitEnd: DateTime(2026, 7, 12),
        postStart: DateTime(2026, 7, 6),
        postEnd: DateTime(2026, 7, 19),
      ).asDuplicate(now: now);

      expect(copy.validate(now: now), isNull);
    });

    test('締切がまだ先の案件は日付を変えない', () {
      final CampaignDraft source = draft(
        applyEnd: DateTime(2026, 9, 1),
        visitStart: DateTime(2026, 9, 2),
        visitEnd: DateTime(2026, 9, 8),
        postStart: DateTime(2026, 9, 2),
        postEnd: DateTime(2026, 9, 15),
      );
      final CampaignDraft copy = source.asDuplicate(now: now);

      expect(copy.applyEndDate, source.applyEndDate);
      expect(copy.postEndDate, source.postEndDate);
    });

    test('一覧で見分けられるようタイトルに接尾辞を付ける', () {
      final CampaignDraft copy = draft(
        title: ' 夏の新メニュー ',
        applyEnd: DateTime(2026, 9, 1),
        visitStart: DateTime(2026, 9, 2),
        visitEnd: DateTime(2026, 9, 8),
        postStart: DateTime(2026, 9, 2),
        postEnd: DateTime(2026, 9, 15),
      ).asDuplicate(now: now);

      expect(copy.title, '夏の新メニュー（コピー）');
    });

    test('条件・ハッシュタグ・提供内容は引き継ぐ', () {
      const Criteria criteria = CriteriaGroup(
        op: LogicalOp.and,
        children: <Criteria>[
          AttributeCriteria(
            attribute: CriteriaAttribute.age,
            comparator: Comparator.gte,
            value: 20,
          ),
        ],
      );
      final CampaignDraft copy = draft(
        applyEnd: DateTime(2026, 9, 1),
        visitStart: DateTime(2026, 9, 2),
        visitEnd: DateTime(2026, 9, 8),
        postStart: DateTime(2026, 9, 2),
        postEnd: DateTime(2026, 9, 15),
        criteria: criteria,
      ).asDuplicate(now: now);

      expect(copy.criteria?.toJson(), criteria.toJson());
      expect(copy.normalizedHashtags, <String>['#カフェ巡り']);
      expect(copy.rewardValueJpy, 1200);
      expect(copy.quota, 2);
    });

    test('複製元の配列を書き換えても複製に影響しない', () {
      final CampaignDraft source = draft(
        applyEnd: DateTime(2026, 9, 1),
        visitStart: DateTime(2026, 9, 2),
        visitEnd: DateTime(2026, 9, 8),
        postStart: DateTime(2026, 9, 2),
        postEnd: DateTime(2026, 9, 15),
      );
      final CampaignDraft copy = source.asDuplicate(now: now);
      source.platforms.add(CampaignPlatform.youtube);

      expect(copy.platforms, <CampaignPlatform>{CampaignPlatform.instagram});
    });
  });

  group('ClientCampaign の一時停止', () {
    ClientCampaign campaign(String status, {String? suspendedBy}) =>
        ClientCampaign.fromJson(<String, dynamic>{
          'id': 'c1',
          'status': status,
          'title': 't',
          'reward_value_jpy': 100,
          'quota': 1,
          'platforms': <String>['instagram'],
          'apply_end_at': '2026-08-11T23:59:59Z',
          'post_start_at': '2026-08-12T00:00:00Z',
          'post_end_at': '2026-08-25T23:59:59Z',
          'created_at': '2026-08-01T00:00:00Z',
          'suspended_by': suspendedBy,
        });

    test('募集中は一時停止できる', () {
      expect(campaign('recruiting').canToggleSuspension, isTrue);
      expect(campaign('recruiting').isSuspended, isFalse);
    });

    test('自分で止めた案件は再開できる', () {
      final ClientCampaign target =
          campaign('suspended', suspendedBy: 'client');
      expect(target.isSuspended, isTrue);
      expect(target.canToggleSuspension, isTrue);
    });

    test('運営が止めた案件は再開の操作を出さない', () {
      final ClientCampaign target = campaign('suspended', suspendedBy: 'admin');
      expect(target.isSuspended, isTrue);
      expect(target.canToggleSuspension, isFalse);
    });

    test('下書き・完了は一時停止の対象外', () {
      expect(campaign('draft').canToggleSuspension, isFalse);
      expect(campaign('completed').canToggleSuspension, isFalse);
    });

    test('一時停止中でも編集・取り下げはできる', () {
      expect(campaign('suspended', suspendedBy: 'client').isEditable, isTrue);
    });
  });

  group('CriteriaTemplate', () {
    CriteriaTemplate template(Map<String, dynamic> criteria) =>
        CriteriaTemplate.fromJson(<String, dynamic>{
          'id': 't1',
          'name': 'よく使う条件',
          'criteria': criteria,
          'created_at': '2026-08-01T00:00:00Z',
        });

    test('条件の件数と結合方法を要約する', () {
      expect(
        template(<String, dynamic>{
          'op': 'AND',
          'children': <dynamic>[
            <String, dynamic>{'attr': 'age', 'cmp': '>=', 'value': 20},
            <String, dynamic>{
              'metric': 'followers',
              'platform': 'instagram',
              'window': 30,
              'cmp': '>=',
              'value': 1000,
            },
          ],
        }).summary,
        '条件 2 件・すべて満たす',
      );
      expect(
        template(<String, dynamic>{
          'op': 'OR',
          'children': <dynamic>[
            <String, dynamic>{'attr': 'age', 'cmp': '>=', 'value': 20},
          ],
        }).summary,
        '条件 1 件・いずれかを満たす',
      );
      expect(
        template(<String, dynamic>{'op': 'AND', 'children': <dynamic>[]})
            .summary,
        '条件なし',
      );
    });

    test('要約に条件の中身（指標名や値）を含めない', () {
      // 一覧に出す文字列なので、条件そのものは書かない。
      final String summary = template(<String, dynamic>{
        'op': 'AND',
        'children': <dynamic>[
          <String, dynamic>{
            'metric': 'followers',
            'platform': 'instagram',
            'window': 30,
            'cmp': '>=',
            'value': 1000,
          },
        ],
      }).summary;
      expect(summary.contains('1000'), isFalse);
      expect(summary.contains('followers'), isFalse);
    });
  });
}
