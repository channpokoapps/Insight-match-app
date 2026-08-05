/// Supabase Auth を用いた認証処理をまとめるファイル。
///
/// メールアドレス + パスワード、または Google アカウントで登録・ログインする。
/// Instagram はログイン手段として使わない（OI-26 決定済み）。
///
/// Google は Web / Android とも **ID トークン方式**に統一している。
/// Web でも `signInWithOAuth`（ページ遷移するリダイレクト方式）は使わない。
/// リダイレクト方式は「Supabase の Redirect URLs に起動オリジンが登録済み」
/// かつ「PKCE の code_verifier が戻り先と同じオリジンの localStorage にある」
/// という遠隔設定に依存し、外れると **エラーも出さずにログイン画面へ戻る**。
/// GIS はページを離れずその場で ID トークンを返すため、この依存が消える。
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

  /// google_sign_in の初期化。プロセス内で 1 回だけ走らせる。
  ///
  /// v7 系の `initialize()` は 2 回目の呼び出しで StateError を投げるため、
  /// 完了フラグではなく Future 自体を共有し、同時に押されても 1 回に畳む。
  /// 失敗したときは null に戻して再試行できるようにする。
  static Future<void>? _googleInitialization;

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

  /// Google サインインを使える状態にする。
  ///
  /// Web はここで GIS（Google Identity Services）のクライアント ID を渡す。
  /// これが済むまで GIS のボタンは描画できないため、ボタン側が表示前に呼ぶ。
  ///
  /// 例外:
  /// - [AppFailure] ビルド設定に「ウェブ」クライアント ID が無い場合。
  Future<void> ensureGoogleSignInReady() =>
      _googleInitialization ??= _initializeGoogleSignIn();

  Future<void> _initializeGoogleSignIn() async {
    try {
      if (Env.googleWebClientId.isEmpty) {
        // 未注入のまま initialize() すると、Web は assert で落ち、Android は
        // idToken が null で返るだけで「なぜかログインできない」失敗になる。
        // ビルド設定の不備だと分かる形でここで止める。
        throw const AppFailure(
          FailureKind.unknown,
          'Google ログインは現在設定中です。メールアドレスでご登録ください。',
        );
      }
      // GCP の「ウェブ」クライアント ID を、Web は GIS の clientId として、
      // Android は ID トークンの発行先（serverClientId）として使う。
      // Android クライアント ID ではないことに注意（supabase.md §4.2）。
      // Web 実装は serverClientId を受け付けない（assert で落ちる）。
      await _googleSignIn.initialize(
        clientId: kIsWeb ? Env.googleWebClientId : null,
        serverClientId: kIsWeb ? null : Env.googleWebClientId,
      );
    } on Object catch (e, s) {
      // 失敗した Future を握ったままだと以後ずっと初期化済み扱いになる。
      _googleInitialization = null;
      if (e is! AppFailure) {
        AppLogger.error('auth.google_init_failed', AppFailure.from(e).code, s);
      }
      rethrow;
    }
  }

  /// Google サインインの結果が流れるストリーム。
  ///
  /// Web の GIS ボタンも Android の [startGoogleSignIn] も、成功すると
  /// ここに [GoogleSignInAuthenticationEventSignIn] が流れる。失敗は
  /// [GoogleSignInException] のストリームエラーとして届く。
  Stream<GoogleSignInAuthenticationEvent> get googleAuthenticationEvents =>
      _googleSignIn.authenticationEvents;

  /// 端末の Google アカウント選択を開始する（Web 以外）。
  ///
  /// Web では使えない。GIS は自分が描画したボタン経由でしか認証を開始できず、
  /// `authenticate()` は UnimplementedError を投げる。
  /// 結果は [googleAuthenticationEvents] に流れる。
  Future<void> startGoogleSignIn() async {
    await ensureGoogleSignInReady();
    await _googleSignIn.authenticate();
  }

  /// 進行中の ID トークン交換。二重実行を防ぐために共有する。
  ///
  /// GIS のサインイン結果は購読している全リスナーに届く。ログイン画面の上に
  /// 新規登録画面が積まれていると両方のボタンが受け取るため、素直に交換すると
  /// 2 本目が失敗し、遷移済みの画面にエラーだけが残る。
  static Future<void>? _pendingGoogleExchange;

  /// Google から受け取った ID トークンで Supabase のセッションを張る。
  ///
  /// Web もこの経路を使う。ページを離れないため、リダイレクト方式のように
  /// 戻り先オリジンの登録漏れで無言に失敗することがない。
  Future<void> signInWithGoogleAccount(GoogleSignInAccount account) {
    return _pendingGoogleExchange ??= _exchangeGoogleIdToken(account);
  }

  Future<void> _exchangeGoogleIdToken(GoogleSignInAccount account) async {
    try {
      await _signInWithGoogleIdToken(account);
    } finally {
      _pendingGoogleExchange = null;
    }
  }

  Future<void> _signInWithGoogleIdToken(GoogleSignInAccount account) async {
    final String? idToken = account.authentication.idToken;
    if (idToken == null) {
      AppLogger.error('auth.google_failed', 'no_id_token', StackTrace.current);
      throw const AppFailure(
        FailureKind.unknown,
        'Google ログインに失敗しました。時間をおいて再度お試しください。',
      );
    }
    try {
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } on AuthException catch (e, s) {
      AppLogger.error('auth.google_failed', e.code ?? 'auth_error', s);
      throw const AppFailure(
        FailureKind.unauthorized,
        'Google ログインに失敗しました。時間をおいて再度お試しください。',
      );
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('auth.google_failed', failure.code, s);
      throw failure;
    }
  }

  /// Google サインインの失敗を画面に出してよい文言へ変換する。
  ///
  /// 利用者がダイアログを閉じただけの中断は null を返す（エラーではない）。
  /// ただし `canceled` は「閉じた」以外に、署名証明書の SHA-1 未登録や
  /// JavaScript 生成元の未登録で資格情報を発行できなかった場合にも返る。
  /// 説明文が付いているのはその後者なので、黙って戻さずエラーとして扱う。
  /// 説明文そのものは内部状態を含みうるため画面には出さない（AGENTS.md R-7）。
  static AppFailure? describeGoogleFailure(Object error) {
    if (error is AppFailure) {
      return error;
    }
    if (error is! GoogleSignInException) {
      return AppFailure.from(error);
    }
    final String? detail = error.description?.trim();
    final bool userClosedDialog =
        error.code == GoogleSignInExceptionCode.canceled &&
            (detail == null || detail.isEmpty);
    if (userClosedDialog) {
      return null;
    }
    switch (error.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return const AppFailure(
          FailureKind.unknown,
          'Google ログインの設定が完了していないため利用できません。'
          'メールアドレスでのログインをお試しください。',
        );
      case GoogleSignInExceptionCode.uiUnavailable:
        return const AppFailure(
          FailureKind.unknown,
          'Google のログイン画面を開けませんでした。'
          'ポップアップのブロックを解除して再度お試しください。',
        );
      case GoogleSignInExceptionCode.canceled:
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.userMismatch:
      case GoogleSignInExceptionCode.unknownError:
        return const AppFailure(
          FailureKind.unknown,
          'Google ログインに失敗しました。時間をおいて再度お試しください。',
        );
    }
  }

  /// テスト用。プロセス共有の初期化状態・進行中の交換を捨てる。
  @visibleForTesting
  static void debugResetGoogleSignIn() {
    _googleInitialization = null;
    _pendingGoogleExchange = null;
  }

  /// ログアウトする。
  Future<void> signOut() => _client.auth.signOut();
}

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
  (Ref ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// 認証コールバックで発生した失敗。無ければ null。
///
/// Google はページを離れなくなったが、確認メール・パスワード再設定メールの
/// リンクは今も別ページから戻ってくるため、呼び出し元には例外が返らない
/// （リンクを開いた時点でアプリは起動し直している）。
/// supabase_flutter は復帰後の `getSessionFromUrl()` の失敗を
/// `onAuthStateChange` のストリームエラーとして通知するので、それを拾う。
/// 拾わないと「リンクを開いたのに何も起きない」だけの状態になり、
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
