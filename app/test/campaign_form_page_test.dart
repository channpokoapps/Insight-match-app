import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/masters/master_repository.dart';
import 'package:insight_match/features/campaign/data/client_campaign_repository.dart';
import 'package:insight_match/features/campaign/presentation/campaign_form_page.dart';
import 'package:insight_match/features/campaign/presentation/criteria_builder.dart';
import 'package:insight_match/features/search/domain/masked_count.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 案件作成フォームが、店舗プロフィールの取得結果に依存せず開けることを確かめる。
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
    expect(find.text('公開する'), findsOneWidget);

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
}
