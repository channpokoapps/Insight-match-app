import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/campaign/domain/campaign.dart';
import 'package:insight_match/shared/widgets/campaign_card.dart';

void main() {
  CampaignListItem item({
    bool isEligible = true,
    bool hasApplied = false,
    DateTime? applyEndAt,
    String rewardDescription = 'ドリンク1杯無料 + 謝礼3,000円',
  }) {
    final DateTime now = DateTime.now();
    return CampaignListItem(
      id: 'campaign-1',
      title: '新メニュー試食のPR投稿',
      storeName: 'カフェ・テスト',
      rewardDescription: rewardDescription,
      rewardValueJpy: 3000,
      applyEndAt: applyEndAt ?? now.add(const Duration(days: 30)),
      postStartAt: now,
      postEndAt: now.add(const Duration(days: 60)),
      isEligible: isEligible,
      hasApplied: hasApplied,
    );
  }

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  testWidgets('条件を満たす案件は報酬内容を表示する', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(CampaignCard(campaign: item(), onTap: () {})),
    );

    expect(find.text('ドリンク1杯無料 + 謝礼3,000円'), findsOneWidget);
    expect(find.text('応募条件を満たすと詳細が見られます'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('条件を満たさない案件は報酬内容を表示しない', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(CampaignCard(campaign: item(isEligible: false), onTap: () {})),
    );

    expect(find.text('ドリンク1杯無料 + 謝礼3,000円'), findsNothing);
    expect(find.text('応募条件を満たすと詳細が見られます'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('応募済みの案件はバッジを表示する', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(CampaignCard(campaign: item(hasApplied: true), onTap: () {})),
    );

    expect(find.text('応募済み'), findsOneWidget);
  });

  testWidgets('締切まで3日以内は締切間近と表示する', (WidgetTester tester) async {
    final DateTime soon = DateTime.now().add(const Duration(days: 2));
    await tester.pumpWidget(
      wrap(CampaignCard(campaign: item(applyEndAt: soon), onTap: () {})),
    );

    expect(find.textContaining('締切間近'), findsOneWidget);
  });

  testWidgets('タップで onTap が呼ばれる', (WidgetTester tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      wrap(CampaignCard(campaign: item(), onTap: () => tapped = true)),
    );

    await tester.tap(find.byType(CampaignCard));
    expect(tapped, isTrue);
  });
}
