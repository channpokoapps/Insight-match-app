/// Supabase Auth を用いた認証処理をまとめるファイル。
///
/// メールアドレス + パスワード、または Google アカウントで登録・ログインする。
/// Instagram はログイン手段として使わない（OI-26 決定済み）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env/env.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';

/// 認証処理を提供するリポジトリ。
///
/// 画面から `SupabaseClient.auth` を直接触らせないための唯一の入口。
class AuthRepository {
  /// リポジトリを生成する。
  ///
  /// [client] Supabase クライアント。
  /// [googleSignIn] テスト用の google_sign_in 差し替え。省略時は共有インスタンス。
  AuthRepository(this._client, {GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final SupabaseClient _client;
  final GoogleSignIn _googleSignIn;

  /// google_sign_in の初期化が済んでいるかどうか。
  ///
  /// v7 系は authenticate() の前に一度だけ initialize() を要求するため、
  /// プロセス内で共有するフラグで多重初期化を防ぐ。
  static bool _googleSignInInitialized = false;

  /// OAuth・メールリンクの戻り先 URL。http(s) で起動していない場合は null。
  ///
  /// 末尾の `/` が重要: Supabase の Redirect URLs は `https://host/**` の
  /// 形式で登録されており、素の origin はパス区切りの `/` を含まないため
  /// 一致せず、Supabase はエラーを返さずに Site URL へフォールバックする。
  /// その場合 PKCE の code_verifier がログイン開始オリジンの localStorage に
  /// しか無いためログインは無言で失敗する（supabase.md §4.1）。
  static String? webRedirectUrl([Uri? base]) {
    final Uri uri = base ?? Uri.base;
    final bool isHttp =
        uri.hasAuthority && (uri.scheme == 'http' || uri.scheme == 'https');
    return isHttp ? '${uri.origin}/' : null;
  }

  /// メールアドレスとパスワードでログインする。
  ///
  /// 例外:
  /// - [AppFailure] 認証に失敗した場合。
  ///   「メールアドレスが存在しない」と「パスワードが違う」は区別しない
  ///   （アカウント存在の推測を防ぐ）。
  Future<void> signInWithPassword(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e, s) {
      AppLogger.error('auth.sign_in_failed', e.code ?? 'auth_error', s);
      if (e.code == 'email_not_confirmed') {
        throw const AppFailure(
          FailureKind.unauthorized,
          'メールアドレスの確認が完了していません。届いた確認メールのリンクを開いてください。',
        );
      }
      throw const AppFailure(
        FailureKind.unauthorized,
        'メールアドレスまたはパスワードが正しくありません。',
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('auth.sign_in_failed', failure.code, s);
      throw failure;
    }
  }

  /// メールアドレスとパスワードでアカウントを作成する。
  ///
  /// 確認メールの送信までを行う。すでに登録済みのメールアドレスでも
  /// 例外にはせず正常に戻す（存在の推測を防ぐため、画面は常に
  /// 「確認メールを送信しました」と案内する）。
  Future<void> signUp(String email, String password) async {
    try {
      // Web では確認リンクの戻り先を登録操作をしたオリジンに固定する。
      // 渡さないと常に Site URL に着地し、プレビュー環境や localhost で
      // 登録した場合にオリジン不一致で確認が完了しない。
      await _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: kIsWeb ? webRedirectUrl() : null,
      );
    } on AuthException catch (e, s) {
      AppLogger.error('auth.sign_up_failed', e.code ?? 'auth_error', s);
      if (e.code == 'user_already_exists' || e.code == 'email_exists') {
        return;
      }
      if (e.code == 'weak_password') {
        throw const AppFailure(
          FailureKind.conflict,
          'このパスワードは使用できません。より複雑なものを設定してください。',
        );
      }
      throw const AppFailure(
        FailureKind.unknown,
        '登録に失敗しました。時間をおいて再度お試しください。',
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('auth.sign_up_failed', failure.code, s);
      throw failure;
    }
  }

  /// パスワード再設定メールを送信する。
  ///
  /// リンク先は Web 版（Supabase の Site URL）。開くと復旧セッションで
  /// ログインされ、`AuthChangeEvent.passwordRecovery` を検知した router が
  /// 新パスワード設定画面へ誘導する。
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      // Web では再設定リンクの戻り先を操作中のオリジンに固定する（signUp と同じ理由）。
      // Android は null のままメールリンクを Web 版（Site URL）に着地させる。
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: kIsWeb ? webRedirectUrl() : null,
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('auth.reset_mail_failed', failure.code, s);
      // 存在しないメールアドレスかどうかを画面に伝えない。
      if (failure.kind != FailureKind.network) {
        return;
      }
      throw failure;
    }
  }

  /// 復旧セッション中に新しいパスワードを設定する。
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e, s) {
      AppLogger.error('auth.update_password_failed', e.code ?? 'auth_error', s);
      if (e.code == 'same_password') {
        throw const AppFailure(
          FailureKind.conflict,
          '現在と同じパスワードは設定できません。',
        );
      }
      throw const AppFailure(
        FailureKind.unknown,
        'パスワードの変更に失敗しました。再設定メールからやり直してください。',
      );
    }
  }

  /// Google アカウントでログインする（初回は自動的にアカウント作成になる）。
  ///
  /// Web は Supabase の OAuth リダイレクトで完結し、Android は
  /// google_sign_in v7 で ID トークンを取得して `signInWithIdToken` に渡す。
  /// 利用者がダイアログを閉じた（キャンセルした）場合は false を返す。
  ///
  /// 戻り値はログイン処理が開始・完了したら true。
  Future<bool> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web はブラウザのリダイレクトで完結する（google_sign_in 不要）。
        // 戻り先はアプリの起動 URL。Supabase の Redirect URLs に登録しておく。
        return _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: webRedirectUrl(),
        );
      }
      if (Env.googleWebClientId.isEmpty) {
        throw const AppFailure(
          FailureKind.unknown,
          'Google ログインは現在設定中です。メールアドレスでご登録ください。',
        );
      }
      if (!_googleSignInInitialized) {
        // serverClientId には GCP の「ウェブ」クライアント ID を渡す。
        // Android クライアント ID ではないことに注意（supabase.md §4.2）。
        await _googleSignIn.initialize(serverClientId: Env.googleWebClientId);
        _googleSignInInitialized = true;
      }
      final GoogleSignInAccount account = await _googleSignIn.authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AppFailure(
          FailureKind.unknown,
          'Google ログインに失敗しました。時間をおいて再度お試しください。',
        );
      }
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      return true;
    } on GoogleSignInException catch (e, s) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // 利用者による中断はエラーではない。
        return false;
      }
      AppLogger.error('auth.google_failed', e.code.name, s);
      throw const AppFailure(
        FailureKind.unknown,
        'Google ログインに失敗しました。時間をおいて再度お試しください。',
      );
    } on AppFailure {
      rethrow;
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('auth.google_failed', failure.code, s);
      throw failure;
    }
  }

  /// ログアウトする。
  Future<void> signOut() => _client.auth.signOut();
}

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
  (Ref ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// OAuth コールバックで発生した失敗。無ければ null。
///
/// Web の Google ログインは別ページへ遷移してから戻るため、`signInWithGoogle()`
/// の呼び出し元には例外が返らない（呼び出したページはもう存在しない）。
/// supabase_flutter は復帰後の `getSessionFromUrl()` の失敗を
/// `onAuthStateChange` のストリームエラーとして通知するので、それを拾う。
/// 拾わないと「アカウントを選んだのに何も起きない」だけの状態になり、
/// 利用者にも開発者にも原因が見えない。
final Provider<AppFailure?> authCallbackFailureProvider =
    Provider<AppFailure?>((Ref ref) {
  if (ref.watch(authStateProvider).error == null) {
    return null;
  }
  // 例外の本文は内部状態を含みうるため画面には出さない（AGENTS.md R-7）。
  // 原因の切り分けに使うコードは app_router.dart でログにだけ残す。
  return const AppFailure(
    FailureKind.unauthorized,
    'ログインを完了できませんでした。お手数ですが、もう一度お試しください。',
  );
});
