import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/campaign/domain/campaign_draft.dart';
import 'package:insight_match/features/campaign/domain/client_campaign.dart';
import 'package:insight_match/features/search/domain/criteria.dart';

Map<String, dynamic> _row({
  String status = 'recruiting',
  Object? criteria,
  Object? visitStartAt = '2026-08-12T00:00:00+09:00',
  Object? visitEndAt = '2026-08-18T23:59:59+09:00',
}) =>
    <String, dynamic>{
      'id': 'campaign-1',
      'status': status,
      'title': '編集対象の案件',
      'store_name_snapshot': 'テストカフェ',
      'genre_id': 3,
      'reward_description': 'コース料理 1名分',
      'reward_value_jpy': 5000,
      'quota': 3,
      'platforms': <String>['instagram', 'tiktok'],
      'criteria': criteria,
      'apply_end_at': '2026-08-11T23:59:59+09:00',
      'visit_start_at': visitStartAt,
      'visit_end_at': visitEndAt,
      'post_start_at': '2026-08-12T00:00:00+09:00',
      'post_end_at': '2026-08-25T23:59:59+09:00',
      'required_content': '写真3枚以上',
      'prefecture_id': 27,
      'city_id': 100,
      'latitude': 34.7,
      'longitude': 135.5,
      'nearest_station_id': 42,
    };

void main() {
  group('EditableCampaign.fromRows', () {
    test('保存済みの案件をフォームの入力内容へ戻す', () {
      final EditableCampaign campaign = EditableCampaign.fromRows(
        row: _row(),
        tags: <Map<String, dynamic>>[
          <String, dynamic>{'tag': '#PR', 'is_mandatory': true},
          <String, dynamic>{'tag': '#カフェ巡り', 'is_mandatory': false},
        ],
        images: <Map<String, dynamic>>[
          <String, dynamic>{'storage_path': 'campaign-1/a.jpg', 'sort_order': 0},
        ],
        applicantCount: 0,
      );

      expect(campaign.draft.title, '編集対象の案件');
      expect(campaign.draft.platforms, <CampaignPlatform>{
        CampaignPlatform.instagram,
        CampaignPlatform.tiktok,
      });
      expect(campaign.draft.rewardValueJpy, 5000);
      expect(campaign.draft.quota, 3);
      expect(campaign.images, <String>['campaign-1/a.jpg']);
      expect(campaign.isLocked, isFalse);
    });

    test('広告表記タグは編集対象のハッシュタグに含めない', () {
      final EditableCampaign campaign = EditableCampaign.fromRows(
        row: _row(),
        tags: <Map<String, dynamic>>[
          <String, dynamic>{'tag': '#PR', 'is_mandatory': true},
          <String, dynamic>{'tag': '#カフェ巡り', 'is_mandatory': false},
        ],
        images: const <Map<String, dynamic>>[],
        applicantCount: 0,
      );
      expect(campaign.draft.hashtags, <String>['#カフェ巡り']);
    });

    test('応募が 1 件でもあれば編集ロック状態になる', () {
      final EditableCampaign campaign = EditableCampaign.fromRows(
        row: _row(),
        tags: const <Map<String, dynamic>>[],
        images: const <Map<String, dynamic>>[],
        applicantCount: 1,
      );
      expect(campaign.isLocked, isTrue);
    });

    test('訪問期間が未設定の案件は報告期間で補う', () {
      final EditableCampaign campaign = EditableCampaign.fromRows(
        row: _row(visitStartAt: null, visitEndAt: null),
        tags: const <Map<String, dynamic>>[],
        images: const <Map<String, dynamic>>[],
        applicantCount: 0,
      );
      expect(campaign.draft.visitStartDate,
          DateTime.parse('2026-08-12T00:00:00+09:00').toLocal());
      expect(campaign.draft.visitEndDate,
          DateTime.parse('2026-08-25T23:59:59+09:00').toLocal());
    });

    test('保存済みの条件式を読み戻す', () {
      final EditableCampaign campaign = EditableCampaign.fromRows(
        row: _row(criteria: <String, dynamic>{
          'op': 'AND',
          'children': <dynamic>[
            <String, dynamic>{'attr': 'age', 'cmp': '>=', 'value': 20},
          ],
        }),
        tags: const <Map<String, dynamic>>[],
        images: const <Map<String, dynamic>>[],
        applicantCount: 0,
      );
      expect(campaign.criteria, isA<CriteriaGroup>());
      expect((campaign.criteria! as CriteriaGroup).children, hasLength(1));
    });

    test('投稿者の識別情報やインサイト値を持たない', () {
      // PR依頼者向けの型に投稿者由来のフィールドを作らない（AGENTS.md R-5 / §3）。
      final EditableCampaign campaign = EditableCampaign.fromRows(
        row: _row(),
        tags: const <Map<String, dynamic>>[],
        images: const <Map<String, dynamic>>[],
        applicantCount: 3,
      );
      expect(campaign.applicantCount, 3);
      expect(
        campaign.toString().contains('creator'),
        isFalse,
        reason: '応募者の識別情報を持たせない',
      );
    });
  });

  group('CampaignDraft.toUpdateJson', () {
    CampaignDraft draft({Criteria? criteria}) => CampaignDraft(
          title: ' 更新後のタイトル ',
          storeName: 'テストカフェ',
          platforms: <CampaignPlatform>{CampaignPlatform.instagram},
          rewardDescription: 'ランチ 1名分',
          rewardValueJpy: 1200,
          quota: 2,
          applyEndDate: DateTime(2026, 8, 11),
          visitStartDate: DateTime(2026, 8, 12),
          visitEndDate: DateTime(2026, 8, 18),
          postStartDate: DateTime(2026, 8, 12),
          postEndDate: DateTime(2026, 8, 25),
          requiredContent: '写真3枚以上',
          criteria: criteria,
        );

    test('状態と応募開始日時は編集で変更しない', () {
      final Map<String, dynamic> json = draft().toUpdateJson();
      expect(json.containsKey('status'), isFalse);
      expect(json.containsKey('apply_start_at'), isFalse);
      expect(json.containsKey('published_at'), isFalse);
      expect(json.containsKey('client_id'), isFalse);
    });

    test('前後の空白を落として送る', () {
      expect(draft().toUpdateJson()['title'], '更新後のタイトル');
    });

    test('条件が未設定なら criteria 列を送らない', () {
      expect(draft().toUpdateJson().containsKey('criteria'), isFalse);
    });

    test('条件があれば criteria を送る', () {
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
      expect(
        draft(criteria: criteria).toUpdateJson()['criteria'],
        criteria.toJson(),
      );
    });
  });

  group('ClientCampaign', () {
    ClientCampaign campaign(String status) => ClientCampaign.fromJson(
          <String, dynamic>{
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
          },
        );

    test('編集・取り下げできる状態を判定する', () {
      expect(campaign('draft').isEditable, isTrue);
      expect(campaign('recruiting').isEditable, isTrue);
      expect(campaign('screening').isEditable, isTrue);
      expect(campaign('completed').isEditable, isFalse);
      expect(campaign('cancelled').isEditable, isFalse);
      expect(campaign('in_progress').isEditable, isFalse);
    });
  });
}
