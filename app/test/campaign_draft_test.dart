import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/campaign/domain/campaign_draft.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 4, 10, 30);

  CampaignDraft draft({
    String title = '新作コースを紹介してください',
    String storeName = 'テストカフェ',
    Set<CampaignPlatform>? platforms,
    String rewardDescription = 'コース料理+ドリンク 1名分',
    int? rewardValueJpy = 5000,
    int? quota = 3,
    DateTime? applyEndDate,
    DateTime? visitStartDate,
    DateTime? visitEndDate,
    DateTime? postStartDate,
    DateTime? postEndDate,
    String requiredContent = '写真3枚以上',
    List<String> hashtags = const <String>[],
  }) =>
      CampaignDraft(
        title: title,
        storeName: storeName,
        platforms: platforms ??
            <CampaignPlatform>{
              CampaignPlatform.instagram,
              CampaignPlatform.tiktok,
            },
        rewardDescription: rewardDescription,
        rewardValueJpy: rewardValueJpy,
        quota: quota,
        applyEndDate: applyEndDate ?? DateTime(2026, 8, 11),
        visitStartDate: visitStartDate ?? DateTime(2026, 8, 12),
        visitEndDate: visitEndDate ?? DateTime(2026, 8, 18),
        postStartDate: postStartDate ?? DateTime(2026, 8, 12),
        postEndDate: postEndDate ?? DateTime(2026, 8, 25),
        requiredContent: requiredContent,
        hashtags: hashtags,
      );

  group('CampaignDraft.validateStep', () {
    test('その段階に無い項目の不足では止めない', () {
      // 未入力の後続段階を理由に進行を止めない（段階入力の前提）。
      expect(
        draft(requiredContent: '', quota: null)
            .validateStep(CampaignFormStep.basics, now: now),
        isNull,
      );
      expect(
        draft(title: '').validateStep(CampaignFormStep.terms, now: now),
        isNull,
      );
      expect(
        draft(title: '', quota: null)
            .validateStep(CampaignFormStep.instructions, now: now),
        isNull,
      );
    });

    test('その段階の項目の不足は検出する', () {
      expect(
        draft(title: ' ').validateStep(CampaignFormStep.basics, now: now),
        contains('タイトル'),
      );
      expect(
        draft(quota: 0).validateStep(CampaignFormStep.terms, now: now),
        contains('募集人数'),
      );
      expect(
        draft(visitStartDate: DateTime(2026, 8, 11))
            .validateStep(CampaignFormStep.terms, now: now),
        contains('訪問開始日'),
      );
      expect(
        draft(requiredContent: '')
            .validateStep(CampaignFormStep.instructions, now: now),
        contains('必須投稿内容'),
      );
    });

    test('応募条件と確認の段階はここでは検証しない', () {
      // 条件式の検証は CriteriaEditor が持つ。
      expect(
        draft().validateStep(CampaignFormStep.criteria, now: now),
        isNull,
      );
      expect(
        draft(title: '').validateStep(CampaignFormStep.confirm, now: now),
        isNull,
      );
    });
  });

  group('CampaignFormStep', () {
    test('先頭と末尾では前後に進みすぎない', () {
      expect(CampaignFormStep.basics.previous, CampaignFormStep.basics);
      expect(CampaignFormStep.confirm.next, CampaignFormStep.confirm);
      expect(CampaignFormStep.basics.next, CampaignFormStep.criteria);
      expect(CampaignFormStep.confirm.previous, CampaignFormStep.instructions);
      expect(CampaignFormStep.basics.isFirst, isTrue);
      expect(CampaignFormStep.confirm.isLast, isTrue);
    });
  });

  group('CampaignDraft.validate', () {
    test('すべての項目がそろっていれば null を返す', () {
      expect(draft().validate(now: now), isNull);
    });

    test('必須テキストの不足を検出する', () {
      expect(draft(title: ' ').validate(now: now), contains('タイトル'));
      expect(draft(storeName: '').validate(now: now), contains('店舗名'));
      expect(
          draft(rewardDescription: '').validate(now: now), contains('提供内容'));
      expect(
          draft(requiredContent: ' ').validate(now: now), contains('必須投稿内容'));
    });

    test('投稿対象 SNS は 1 つ以上必要', () {
      expect(draft(platforms: <CampaignPlatform>{}).validate(now: now),
          contains('SNS'));
    });

    test('想定価格は 0 円以上の入力が必要', () {
      expect(draft(rewardValueJpy: null).validate(now: now), contains('想定価格'));
      expect(draft(rewardValueJpy: -1).validate(now: now), contains('想定価格'));
      expect(draft(rewardValueJpy: 0).validate(now: now), isNull);
    });

    test('募集人数は 1 人以上', () {
      expect(draft(quota: null).validate(now: now), contains('募集人数'));
      expect(draft(quota: 0).validate(now: now), contains('募集人数'));
    });

    test('応募締切日は今日以降', () {
      expect(draft(applyEndDate: DateTime(2026, 8, 3)).validate(now: now),
          contains('応募締切日'));
      // 今日はまだ締め切れる（その日の 23:59 が締切になる）。
      expect(
        draft(
          applyEndDate: DateTime(2026, 8, 4),
          visitStartDate: DateTime(2026, 8, 5),
          visitEndDate: DateTime(2026, 8, 18),
          postStartDate: DateTime(2026, 8, 5),
        ).validate(now: now),
        isNull,
      );
    });

    test('期間は 応募締切 → 訪問 → 報告 の順序を守る', () {
      expect(
        draft(visitStartDate: DateTime(2026, 8, 11)).validate(now: now),
        contains('訪問開始日'),
      );
      expect(
        draft(visitEndDate: DateTime(2026, 8, 11)).validate(now: now),
        contains('訪問終了日'),
      );
      expect(
        draft(postStartDate: DateTime(2026, 8, 11)).validate(now: now),
        contains('報告開始日'),
      );
      expect(
        draft(
          postStartDate: DateTime(2026, 8, 20),
          postEndDate: DateTime(2026, 8, 19),
        ).validate(now: now),
        contains('報告終了日'),
      );
      // 報告終了は訪問終了より前にできない。
      expect(
        draft(
          postStartDate: DateTime(2026, 8, 12),
          postEndDate: DateTime(2026, 8, 15),
        ).validate(now: now),
        contains('報告終了日'),
      );
    });
  });

  group('CampaignDraft.normalizedHashtags', () {
    test('# を補い、空・重複・広告表記タグを除く', () {
      final CampaignDraft target = draft(hashtags: <String>[
        'カフェ巡り',
        '#カフェ巡り',
        ' ',
        '#',
        '#PR',
        'pr',
        '#梅田ランチ',
      ]);
      expect(target.normalizedHashtags, <String>['#カフェ巡り', '#梅田ランチ']);
    });
  });

  group('CampaignDraft.toInsertJson', () {
    test('公開時は recruiting、下書き時は draft になる', () {
      final Map<String, dynamic> published = draft()
          .toInsertJson(clientId: 'client-1', publish: true, now: now);
      expect(published['status'], 'recruiting');
      expect(published['published_at'], isNotNull);

      final Map<String, dynamic> saved = draft()
          .toInsertJson(clientId: 'client-1', publish: false, now: now);
      expect(saved['status'], 'draft');
      expect(saved['published_at'], isNull);
    });

    test('締切・終了は 23:59:59、開始は 0:00 に展開される', () {
      final Map<String, dynamic> json = draft()
          .toInsertJson(clientId: 'client-1', publish: true, now: now);
      expect(DateTime.parse(json['apply_end_at'] as String).toLocal(),
          DateTime(2026, 8, 11, 23, 59, 59));
      expect(DateTime.parse(json['visit_start_at'] as String).toLocal(),
          DateTime(2026, 8, 12));
      expect(DateTime.parse(json['visit_end_at'] as String).toLocal(),
          DateTime(2026, 8, 18, 23, 59, 59));
      expect(DateTime.parse(json['post_start_at'] as String).toLocal(),
          DateTime(2026, 8, 12));
      expect(DateTime.parse(json['post_end_at'] as String).toLocal(),
          DateTime(2026, 8, 25, 23, 59, 59));
      expect(DateTime.parse(json['apply_start_at'] as String).toLocal(), now);
    });

    test('プラットフォームは wire 名の昇順で保存される', () {
      final Map<String, dynamic> json = draft(
        platforms: <CampaignPlatform>{
          CampaignPlatform.youtube,
          CampaignPlatform.instagram,
        },
      ).toInsertJson(clientId: 'client-1', publish: false, now: now);
      expect(json['platforms'], <String>['instagram', 'youtube']);
    });

    test('インサイト実数値に類するフィールドを含まない', () {
      // 型として存在させないことが最大の防御（AGENTS.md §3）。
      final Map<String, dynamic> json = draft()
          .toInsertJson(clientId: 'client-1', publish: true, now: now);
      expect(
        json.keys.where((String key) =>
            key.contains('follower') ||
            key.contains('insight') ||
            key.contains('engagement')),
        isEmpty,
      );
    });
  });
}
