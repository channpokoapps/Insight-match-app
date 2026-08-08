import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/masters/master_repository.dart';
import 'package:insight_match/features/campaign/data/client_campaign_repository.dart';
import 'package:insight_match/features/campaign/presentation/campaign_form_page.dart';
import 'package:insight_match/features/campaign/presentation/criteria_builder.dart';
import 'package:insight_match/features/search/domain/masked_count.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 案件作成フォームが、店舗プロフィールの取得結果に依存せず開けること、
/// および段階を追って入力・確認できることを確かめる。
///
/// 初期値の取得（FR-CMP-02）は入力の手間を省くだけの機能であり、
/// これが落ちても案件作成そのものは続けられなければならない。
void main() {
  List<Override> overrides({Object? storeDefaultsError}) => <Override>[
        storeDefaultsProvider.overrideWith((Ref ref) async {
          final Object? error = storeDefaultsError;
          if (error != null) {
            throw error;
          }
          return const StoreDefaults(storeName: 'テストカフェ', genreId: 3);
        }),
        genresProvider.overrideWith((Ref ref) async => <MasterItem>[
              const MasterItem(id: 3, name: 'カフェ'),
            ]),
        prefecturesProvider.overrideWith((Ref ref) async => <MasterItem>[]),
        matchingCreatorCountProvider.overrideWith(
          (Ref ref, String criteriaJson) async =>
              const MaskedCount(count: 12, masked: false, label: '12人'),
        ),
      ];

  Widget wrap(List<Override> given) => ProviderScope(
        overrides: given,
        child: const MaterialApp(home: CampaignFormPage()),
      );

  /// ①店舗・提供内容 の必須項目を埋める。
  Future<void> fillBasics(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'テスト案件');
    await tester.enterText(find.byType(TextField).at(2), 'コース料理 1名分');
    await tester.enterText(find.byType(TextField).at(3), '5000');
    await tester.pump();
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, '次へ'));
    await tester.pumpAndSettle();
  }

  testWidgets('店舗情報を取得できなくてもフォームを開いて入力できる',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(overrides(
      // 本番 DB にマイグレーションが未反映のときに来る応答。
      storeDefaultsError: const PostgrestException(
        message: 'column client_profiles.genre_ids does not exist',
        code: '42703',
      ),
    )));
    await tester.pumpAndSettle();

    // 画面全体がエラー表示に差し替わらない。
    expect(find.text('案件タイトル'), findsOneWidget);
    expect(find.text('店舗名'), findsOneWidget);

    // 自動入力できなかったことと、続けられることを伝える。
    expect(find.textContaining('店舗情報を自動入力できませんでした'), findsOneWidget);
    expect(find.text('自動入力を再試行'), findsOneWidget);

    // 店舗名は手入力できる。
    await tester.enterText(find.byType(TextField).at(1), '手入力カフェ');
    await tester.pump();
    expect(find.text('手入力カフェ'), findsOneWidget);
  });

  testWidgets('取得できたときは店舗名を自動入力し、注意書きを出さない',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(overrides()));
    await tester.pumpAndSettle();

    expect(find.text('テストカフェ'), findsOneWidget);
    expect(find.textContaining('店舗情報を自動入力できませんでした'), findsNothing);
  });

  testWidgets('最初は 1 段階目だけを出し、公開ボタンは最後まで出さない',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(overrides()));
    await tester.pumpAndSettle();

    expect(find.text('1. 店舗・提供内容'), findsOneWidget);
    expect(find.text('次へ'), findsOneWidget);
    expect(find.text('公開する'), findsNothing);
    // 後の段階の入力欄は同時に出さない（縦に伸ばさないための分割）。
    expect(find.text('募集人数'), findsNothing);
    expect(find.text('必須投稿内容'), findsNothing);
    // 1 段階目に戻るボタンは要らない。
    expect(find.text('戻る'), findsNothing);
  });

  testWidgets('必須項目が空のまま次へ進もうとすると理由を出して止める',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(overrides()));
    await tester.pumpAndSettle();

    await tapNext(tester);

    expect(find.textContaining('案件タイトルを入力してください'), findsOneWidget);
    expect(find.text('1. 店舗・提供内容'), findsOneWidget);
  });

  testWidgets('段階を進めて確認画面まで到達し、入力内容を確認できる',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(overrides()));
    await tester.pumpAndSettle();

    await fillBasics(tester);
    await tapNext(tester); // → ②応募条件
    expect(find.text('2. 応募条件'), findsOneWidget);

    await tapNext(tester); // → ③募集要項（条件なしのままでも進める）
    expect(find.text('3. 募集要項'), findsOneWidget);
    expect(find.text('募集人数'), findsOneWidget);

    await tapNext(tester); // → ④投稿指示
    expect(find.text('4. 投稿指示'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '写真3枚以上');
    await tester.pump();

    await tapNext(tester); // → ⑤確認
    expect(find.text('5. 確認'), findsOneWidget);
    expect(find.text('公開する'), findsOneWidget);
    expect(find.text('下書きとして保存'), findsOneWidget);
    expect(find.text('テスト案件'), findsOneWidget);
    expect(find.text('条件なし（全員が応募できます）'), findsOneWidget);
  });

  testWidgets('確認画面の「修正」でその段階へ戻れる', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(overrides()));
    await tester.pumpAndSettle();

    await fillBasics(tester);
    await tapNext(tester);
    await tapNext(tester);
    await tapNext(tester);
    await tester.enterText(find.byType(TextField).at(1), '写真3枚以上');
    await tester.pump();
    await tapNext(tester);

    // 確認カードは ①店舗 ②条件 ③要項 ④指示 の順。3 枚目の「修正」を押す。
    final Finder editTerms = find.text('修正').at(2);
    await tester.ensureVisible(editTerms);
    await tester.pumpAndSettle();
    await tester.tap(editTerms);
    await tester.pumpAndSettle();

    expect(find.text('3. 募集要項'), findsOneWidget);
  });
}
