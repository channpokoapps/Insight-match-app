import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/auth/auth_callback_trace.dart';
import 'package:insight_match/core/supabase/supabase_providers.dart';
import 'package:insight_match/features/auth/data/auth_repository.dart';
import 'package:insight_match/features/auth/presentation/sign_in_page.dart';
import 'package:insight_match/features/auth/presentation/welcome_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  setUp(AuthRepository.debugResetGoogleSignIn);

  /// 認証ホーム画面（未ログイン時の着地点）を組み立てる。
  Widget wrapWelcome(Stream<AuthState> authState, {Uri? bootUri}) =>
      ProviderScope(
        overrides: <Override>[
          supabaseClientProvider.overrideWithValue(_MockSupabaseClient()),
          authStateProvider.overrideWith((Ref ref) => authState),
          authCallbackTraceProvider.overrideWithValue(
            AuthCallbackTrace.capture(
              bootUri ?? Uri.parse('https://example.web.app/'),
            ),
          ),
        ],
        child: const MaterialApp(home: WelcomePage()),
      );

  Widget wrapSignIn({bool signUpMode = false}) => ProviderScope(
        overrides: <Override>[
          supabaseClientProvider.overrideWithValue(_MockSupabaseClient()),
        ],
        child: MaterialApp(
          home: SignInPage(initialSignUpMode: signUpMode),
        ),
      );

  group('認証ホーム画面', () {
    testWidgets('入口はアカウント作成とログインの 2 つ', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWelcome(Stream<AuthState>.value(
          const AuthState(AuthChangeEvent.initialSession, null),
        )),
      );
      await tester.pump();

      expect(find.text('新規アカウント作成'), findsOneWidget);
      expect(find.text('ログイン'), findsOneWidget);
    });

    testWidgets('メールリンクからの復帰に失敗したら理由を表示する',
        (WidgetTester tester) async {
      // 確認メール・再設定メールのリンクは別ページから戻るため、失敗しても
      // 画面には例外が飛ばない。無言でこの画面に戻るだけにしない。
      await tester.pumpWidget(
        wrapWelcome(Stream<AuthState>.error(
          const AuthException('bad_code_verifier', code: 'bad_code_verifier'),
        )),
      );
      await tester.pump();

      expect(find.text('ログインを完了できませんでした。お手数ですが、もう一度お試しください。'),
          findsOneWidget);
    });

    testWidgets('コールバックが正常なら余計なエラーを出さない',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWelcome(Stream<AuthState>.value(
          const AuthState(AuthChangeEvent.initialSession, null),
        )),
      );
      await tester.pump();

      expect(find.text('ログインを完了できませんでした。お手数ですが、もう一度お試しください。'),
          findsNothing);
    });

    testWidgets('コールバックのエラーは戻り先ホストと理由を添えて出す',
        (WidgetTester tester) async {
      // Supabase が redirect_to を差し替えると、戻り先ホストが想定と変わる。
      // 画面から判別できないと原因にたどり着けない。
      await tester.pumpWidget(
        wrapWelcome(
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
        wrapWelcome(
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
        wrapWelcome(Stream<AuthState>.error(
          const AuthException('code verifier not found in local storage'),
        )),
      );
      await tester.pump();

      expect(find.textContaining('local storage'), findsNothing);
      expect(find.textContaining('verifier'), findsNothing);
    });
  });

  group('ログイン / 新規作成画面', () {
    testWidgets('ログインモードでは Google ボタンとパスワード再設定を出す',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapSignIn());
      await tester.pump();

      expect(find.text('Google で続行'), findsOneWidget);
      expect(find.text('パスワードを忘れた場合'), findsOneWidget);
      expect(find.text('パスワード（確認）'), findsNothing);
    });

    testWidgets('新規作成モードでは確認欄を出し、再設定リンクは出さない',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapSignIn(signUpMode: true));
      await tester.pump();

      expect(find.text('パスワード（確認）'), findsOneWidget);
      expect(find.text('パスワードを忘れた場合'), findsNothing);
      // 初回利用は自動的にアカウント作成になるため、こちらにも Google を出す。
      expect(find.text('Google で続行'), findsOneWidget);
    });

    testWidgets('モードは画面内のリンクで切り替えられる', (WidgetTester tester) async {
      await tester.pumpWidget(wrapSignIn());
      await tester.pump();

      await tester.tap(find.text('はじめての方はアカウントを作成'));
      await tester.pump();

      expect(find.text('アカウントを作成'), findsOneWidget);
      expect(find.text('パスワード（確認）'), findsOneWidget);
    });

    testWidgets('パスワードが一致しなければ送信前に弾く', (WidgetTester tester) async {
      await tester.pumpWidget(wrapSignIn(signUpMode: true));
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextField, 'メールアドレス'), 'a@example.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'パスワード'), 'password1');
      await tester.enterText(
          find.widgetWithText(TextField, 'パスワード（確認）'), 'password2');
      await tester.tap(find.text('アカウントを作成'));
      await tester.pump();

      expect(find.text('パスワード（確認）が一致しません。'), findsOneWidget);
    });
  });

  test('http(s) 以外の URL でも例外を投げない（起動を止めない）', () {
    // Android の Uri.base は file:///... になる。Uri.origin は投げるので、
    // ここで落ちると main() ごと死ぬ。
    final AuthCallbackTrace trace =
        AuthCallbackTrace.capture(Uri.parse('file:///data/user/0/app/'));
    expect(trace.origin, isEmpty);
    expect(trace.isCallback, isFalse);
    expect(trace.host, '-');
  });
}
