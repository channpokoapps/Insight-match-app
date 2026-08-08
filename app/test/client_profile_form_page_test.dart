import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/masters/master_repository.dart';
import 'package:insight_match/features/auth/data/profile_repository.dart';
import 'package:insight_match/features/auth/domain/client_profile.dart';
import 'package:insight_match/features/auth/presentation/client_profile_form_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 登録後に店舗情報を変更する画面（FR-AUTH-07）。
///
/// 保存済みの内容を読めないまま開くと、空欄を保存して登録済みの内容を
/// 消してしまう。読めたときだけフォームを出すことを確かめる。
void main() {
  const ClientProfile saved = ClientProfile(
    storeName: 'テストカフェ',
    genreIds: <int>[3],
    postalCode: '5300001',
    prefectureId: 27,
    cityId: 100,
    addressLine: '梅田1-1-1',
    contactEmail: 'store@example.com',
    description: '駅前のカフェです。',
  );

  List<Override> overrides({Object? error}) => <Override>[
        clientProfileProvider.overrideWith((Ref ref) async {
          final Object? failure = error;
          if (failure != null) {
            throw failure;
          }
          return saved;
        }),
        genresProvider.overrideWith((Ref ref) async => <MasterItem>[
              const MasterItem(id: 3, name: 'カフェ'),
            ]),
        prefecturesProvider.overrideWith((Ref ref) async => <MasterItem>[
              const MasterItem(id: 27, name: '大阪府'),
            ]),
        citiesProvider.overrideWith((Ref ref, int prefectureId) async =>
            <MasterItem>[const MasterItem(id: 100, name: '大阪市北区')]),
      ];

  Widget wrap(List<Override> given) => ProviderScope(
        overrides: given,
        child: const MaterialApp(home: ClientProfileFormPage(isEdit: true)),
      );

  testWidgets('保存済みの店舗情報を読み込んで編集できる', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(overrides()));
    await tester.pumpAndSettle();

    expect(find.text('店舗情報の編集'), findsOneWidget);
    expect(find.text('テストカフェ'), findsOneWidget);
    expect(find.text('梅田1-1-1'), findsOneWidget);
    expect(find.text('store@example.com'), findsOneWidget);
    expect(find.text('駅前のカフェです。'), findsOneWidget);
    // 郵便番号は保存済みの値のまま。住所検索を走らせて上書きしない。
    expect(find.text('5300001'), findsOneWidget);
    expect(find.text('変更を保存'), findsOneWidget);
  });

  testWidgets('読み込めなかったときはフォームを出さずに再試行を促す',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(overrides(
      error: const PostgrestException(message: 'network error'),
    )));
    await tester.pumpAndSettle();

    // 空欄のフォームを見せると、保存で登録済みの内容を消してしまう。
    expect(find.text('店舗・企業名'), findsNothing);
    expect(find.text('変更を保存'), findsNothing);
    expect(find.text('再読み込み'), findsOneWidget);
  });
}
