import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/features/auth/data/auth_repository.dart';
import 'package:insight_match/features/auth/data/profile_repository.dart';
import 'package:insight_match/features/auth/domain/registration_step.dart';
import 'package:insight_match/shared/widgets/splash_page.dart';

/// signOut の呼び出しだけを記録するフェイク。
///
/// 本物の SupabaseClient はコンストラクタでタイマーを起動するため
/// テストでは生成しない（implements + noSuchMethod で回避）。
class _FakeAuthRepository implements AuthRepository {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  testWidgets('登録段階の取得に失敗したら再試行とログアウトの導線を出す',
      (WidgetTester tester) async {
    // fetchRegistrationState が失敗し続けると router はこの画面に留め続ける。
    // 脱出導線が無いと利用者はアプリを使い直せない。
    final _FakeAuthRepository auth = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          registrationStepProvider.overrideWith(
            (Ref ref) => Future<RegistrationState?>.error(Exception('down')),
          ),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(home: SplashPage()),
      ),
    );
    await tester.pump();

    expect(find.text('再試行'), findsOneWidget);
    expect(find.text('ログアウトしてやり直す'), findsOneWidget);

    await tester.tap(find.text('ログアウトしてやり直す'));
    await tester.pump();

    expect(auth.signOutCalls, 1);
  });

  testWidgets('判定中はスプラッシュ（インジケータ）を表示する', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          registrationStepProvider.overrideWith(
            // 完了しない Future = 判定中のまま。
            (Ref ref) => Completer<RegistrationState?>().future,
          ),
        ],
        child: const MaterialApp(home: SplashPage()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('ログアウトしてやり直す'), findsNothing);
  });
}
