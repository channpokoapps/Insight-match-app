import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/auth/auth_callback_trace.dart';
import 'package:insight_match/core/supabase/supabase_providers.dart';
import 'package:insight_match/features/auth/presentation/sign_in_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Widget wrap(Stream<AuthState> authState, {Uri? bootUri}) => ProviderScope(
        overrides: <Override>[
          authStateProvider.overrideWith((Ref ref) => authState),
          authCallbackTraceProvider.overrideWithValue(
            AuthCallbackTrace.capture(
              bootUri ?? Uri.parse('https://example.web.app/'),
            ),
          ),
        ],
        child: const MaterialApp(home: SignInPage()),
      );

  testWidgets('OAuth コールバックが失敗したらログイン画面に理由を表示する',
      (WidgetTester tester) async {
    // Web の Google ログインは別ページから戻ってくるため、失敗しても
    // 画面には例外が飛ばない。無言でログイン画面に戻るだけにしない。
    await tester.pumpWidget(
      wrap(Stream<AuthState>.error(
        const AuthException('bad_code_verifier', code: 'bad_code_verifier'),
      )),
    );
    await tester.pump();

    expect(find.text('ログインを完了できませんでした。お手数ですが、もう一度お試しください。'),
        findsOneWidget);
  });

  testWidgets('コールバックが正常なら余計なエラーを出さない', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(Stream<AuthState>.value(
        const AuthState(AuthChangeEvent.initialSession, null),
      )),
    );
    await tester.pump();

    expect(find.text('ログインを完了できませんでした。お手数ですが、もう一度お試しください。'),
        findsNothing);
    expect(find.text('Google で続行'), findsOneWidget);
  });

  testWidgets('コールバックのエラーは戻り先ホストと理由を添えて出す',
      (WidgetTester tester) async {
    // Supabase が redirect_to を差し替えると、戻り先ホストが想定と変わる。
    // 画面から判別できないと原因にたどり着けない。
    await tester.pumpWidget(
      wrap(
        Stream<AuthState>.value(
          const AuthState(AuthChangeEvent.initialSession, null),
        ),
        bootUri: Uri.parse(
          'https://insight-match-2fbaa.web.app/?error=server_error'
          '&error_description=Unable+to+exchange+external+code',
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('insight-match-2fbaa.web.app'), findsWidgets);
    expect(find.textContaining('server_error'), findsOneWidget);
  });

  testWidgets('認可コードの値そのものは画面に出さない', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        Stream<AuthState>.value(
          const AuthState(AuthChangeEvent.initialSession, null),
        ),
        bootUri: Uri.parse('https://example.web.app/?code=super-secret-code'),
      ),
    );
    await tester.pump();

    expect(find.textContaining('super-secret-code'), findsNothing);
    expect(find.textContaining('認可コードは受信済み'), findsOneWidget);
  });

  testWidgets('失敗の詳細（例外の中身）を画面に出さない', (WidgetTester tester) async {
    // 例外本文には内部状態が含まれうる（AGENTS.md R-7）。
    await tester.pumpWidget(
      wrap(Stream<AuthState>.error(
        const AuthException('code verifier not found in local storage'),
      )),
    );
    await tester.pump();

    expect(find.textContaining('local storage'), findsNothing);
    expect(find.textContaining('verifier'), findsNothing);
  });
}
