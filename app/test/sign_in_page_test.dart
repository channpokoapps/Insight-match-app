import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/auth/auth_callback_trace.dart';
import 'package:insight_match/core/error/app_failure.dart';
import 'package:insight_match/core/supabase/supabase_providers.dart';
import 'package:insight_match/features/auth/data/auth_repository.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:insight_match/features/auth/presentation/sign_in_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  setUp(AuthRepository.debugResetGoogleSignIn);

  // Google ボタンは表示された時点で AuthRepository を読む(GIS の初期化のため)
  // ので、Supabase.initialize() を通っていないテストでも組み立てられるように
  // クライアントを差し替える。
  Widget wrap(Stream<AuthState> authState, {Uri? bootUri}) => ProviderScope(
        overrides: <Override>[
          supabaseClientProvider.overrideWithValue(_MockSupabaseClient()),
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

  testWidgets('Google ボタンは設定が無いと押せず、理由を出す',
      (WidgetTester tester) async {
    // GOOGLE_WEB_CLIENT_ID 未注入のビルドでボタンだけ出すと、押しても何も
    // 起きない画面になる。押せないことと理由が分かる状態を保証する。
    await tester.pumpWidget(
      wrap(Stream<AuthState>.value(
        const AuthState(AuthChangeEvent.initialSession, null),
      )),
    );
    await tester.pump();

    expect(find.text('Google で続行'), findsOneWidget);
    // OutlinedButton.icon は非公開のサブクラスを返すため byType では拾えない。
    final Finder button = find.ancestor(
      of: find.text('Google で続行'),
      matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(
      find.text('Google ログインは現在設定中です。メールアドレスでご登録ください。'),
      findsOneWidget,
    );
  });

  group('AuthRepository.describeGoogleFailure', () {
    test('利用者がダイアログを閉じただけならエラー扱いしない', () {
      expect(
        AuthRepository.describeGoogleFailure(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
        isNull,
      );
    });

    test('説明文つきの canceled は設定不備なのでエラーとして扱う', () {
      // SHA-1 未登録・JavaScript 生成元未登録などはここに来る。黙って戻すと
      // 「アカウントを選んでもログイン画面に戻るだけ」の失敗になる。
      final AppFailure? failure = AuthRepository.describeGoogleFailure(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'origin is not allowed for the given client ID',
        ),
      );
      expect(failure, isNotNull);
    });

    test('失敗の説明文（内部状態）を画面用の文言に混ぜない', () {
      // 例外本文には内部状態が含まれうる（AGENTS.md R-7）。
      final AppFailure? failure = AuthRepository.describeGoogleFailure(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
          description: 'client_id 1234-secret.apps.googleusercontent.com',
        ),
      );
      expect(failure, isNotNull);
      expect(failure!.message, isNot(contains('1234-secret')));
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
