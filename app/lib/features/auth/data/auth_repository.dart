/// Supabase Auth を用いた認証処理をまとめるファイル。
///
/// メールアドレス + パスワード、または Google アカウントで登録・ログインする。
/// Instagram はログイン手段として使わない（OI-26 決定済み）。
///
/// Google は Web / Android とも **ID トークン方式**に統一している
/// （Shift Navi と同じ仕組み）。
/// Web でも `signInWithOAuth`（ページ遷移するリダイレクト方式）は使わない。
/// リダイレクト方式は「Supabase の Redirect URLs に起動オリジンが登録済み」
/// かつ「PKCE の code_verifier が戻り先と同じオリジンの localStorage にある」
/// という遠隔設定に依存し、外れると **エラーも出さずにログイン画面へ戻る**。
///
/// Web はポップアップで Google の ID トークンをその場で受け取り、Android は
/// google_sign_in から受け取る。どちらもページを離れないので上の依存が消える。
///
/// **Firebase Authentication は「Google の ID トークンを取り出す窓口」としてのみ
/// 使う。** アプリの利用者 ID・権限はこれまで通り Supabase Auth（`auth.uid()`）
/// が唯一の正であり、Firebase 側のセッションはトークンを取り出したら破棄する。
library;

// Supabase の gotrue とクラス名（OAuthProvider など）が衝突するため前置詞をつける。
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
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
  /// [firebaseAuth] テスト用の Firebase Auth 差し替え。省略時は既定のインスタンス
  /// （Web の Google ポップアップでのみ使う。未初期化なら参照しない）。
  AuthRepository(
    this._client, {
    GoogleSignIn? googleSignIn,
    fb.FirebaseAuth? firebaseAuth,
  })  : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
        _firebaseAuth = firebaseAuth;

  final SupabaseClient _client;
  final GoogleSignIn _googleSignIn;
  final fb.FirebaseAuth? _firebaseAuth;

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
  /// Web は Firebase Authentication のポップアップで Google の ID トークンを
  /// その場で受け取り、Android は google_sign_in から受け取る。どちらも
  /// 受け取った ID トークンを `signInWithIdToken` で Supabase に渡す。
  ///
  /// 戻り値はログインが完了したら true、利用者がダイアログを閉じたら false。
  ///
  /// 例外:
  /// - [AppFailure] 認証に失敗した場合。
  Future<bool> signInWithGoogle() async {
    try {
      final String? idToken =
          kIsWeb ? await _idTokenFromPopup() : await _idTokenFromDevice();
      if (idToken == null) {
        // 利用者がダイアログを閉じただけ。エラーではない。
        return false;
      }
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      return true;
    } on AppFailure {
      rethrow;
    } on AuthException catch (e, s) {
      // Supabase が ID トークンを受け付けなかった。ほぼ確実に Providers →
      // Google の Authorized Client IDs に発行元のクライアント ID が無い
      // （aud の検証で弾かれる。supabase.md §4.3）。
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

  /// Web: Firebase のポップアップから Google の ID トークンを取り出す。
  ///
  /// 中断されたら null。Firebase Auth を使うのはここだけで、取り出した直後に
  /// Firebase 側のセッションは破棄する（利用者 ID は Supabase のものが唯一）。
  Future<String?> _idTokenFromPopup() async {
    final fb.FirebaseAuth auth = _requireFirebaseAuth();
    final fb.UserCredential result;
    try {
      result = await auth.signInWithPopup(fb.GoogleAuthProvider());
    } on fb.FirebaseAuthException catch (e, s) {
      if (_isPopupDismissed(e.code)) {
        return null;
      }
      AppLogger.error('auth.google_failed', e.code, s);
      if (e.code == 'unauthorized-domain') {
        // Firebase コンソールの「承認済みドメイン」に今のホストが無い。
        // プレビューチャンネルで起きやすい（gcp_firebase.md §2）。
        throw const AppFailure(
          FailureKind.unknown,
          'この URL からは Google ログインを利用できません。'
          '管理者に「承認済みドメイン」の登録を依頼してください。',
        );
      }
      throw const AppFailure(
        FailureKind.unknown,
        'Google ログインに失敗しました。時間をおいて再度お試しください。',
      );
    }
    // Firebase 自身の ID トークンではなく、Google が発行した ID トークンを使う。
    // 前者は aud が Firebase プロジェクトなので Supabase では検証できない。
    final fb.AuthCredential? credential = result.credential;
    final String? idToken =
        credential is fb.OAuthCredential ? credential.idToken : null;
    // セッションを残すと「Firebase にはログイン済みだが Supabase には未ログイン」
    // という食い違いが起きる。取り出したらすぐ捨てる。
    await auth.signOut();
    if (idToken == null) {
      AppLogger.error('auth.google_failed', 'no_id_token', StackTrace.current);
      throw const AppFailure(
        FailureKind.unknown,
        'Google ログインに失敗しました。時間をおいて再度お試しください。',
      );
    }
    return idToken;
  }

  /// ポップアップを閉じられた（＝中断）ことを表すコードかどうか。
  static bool _isPopupDismissed(String code) =>
      code == 'popup-closed-by-user' ||
      code == 'cancelled-popup-request' ||
      code == 'user-cancelled' ||
      code == 'web-context-cancelled';

  /// Android: google_sign_in から Google の ID トークンを取り出す。
  ///
  /// 中断されたら null。
  Future<String?> _idTokenFromDevice() async {
    if (Env.googleWebClientId.isEmpty) {
      // 未注入のまま initialize() すると idToken が null で返るだけで、
      // 「なぜかログインできない」という分かりにくい失敗になる。
      // ビルド設定の不備だと分かる形でここで止める。
      throw const AppFailure(
        FailureKind.unknown,
        'Google ログインは現在設定中です。メールアドレスでご登録ください。',
      );
    }
    final GoogleSignInAccount account;
    try {
      await (_googleInitialization ??= _googleSignIn.initialize(
        // serverClientId には GCP の「ウェブ」クライアント ID を渡す。
        // Android クライアント ID ではないことに注意（supabase.md §4.2）。
        serverClientId: Env.googleWebClientId,
      ));
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e, s) {
      // canceled は「利用者が閉じた」だけでなく、署名証明書の SHA-1 が
      // GCP に未登録などで資格情報を発行できなかった場合にも返る。
      // 後者まで黙って戻すと「アカウントを選んでもログイン画面に戻るだけ」
      // という追えない失敗になるため、説明文が付いていればエラーにする。
      // 説明文そのものは内部状態を含みうるので画面には出さない（R-7）。
      final String? detail = e.description?.trim();
      if (e.code == GoogleSignInExceptionCode.canceled &&
          (detail == null || detail.isEmpty)) {
        return null;
      }
      _googleInitialization = null;
      AppLogger.error('auth.google_failed', e.code.name, s);
      throw const AppFailure(
        FailureKind.unknown,
        'Google ログインに失敗しました。時間をおいて再度お試しください。',
      );
    }
    final String? idToken = account.authentication.idToken;
    if (idToken == null) {
      AppLogger.error('auth.google_failed', 'no_id_token', StackTrace.current);
      throw const AppFailure(
        FailureKind.unknown,
        'Google ログインに失敗しました。時間をおいて再度お試しください。',
      );
    }
    return idToken;
  }

  /// Web の Google ログインに使う Firebase Auth を返す。
  fb.FirebaseAuth _requireFirebaseAuth() {
    final fb.FirebaseAuth? injected = _firebaseAuth;
    if (injected != null) {
      return injected;
    }
    if (Firebase.apps.isEmpty) {
      // main() の Firebase 初期化は設定が無いと黙ってスキップされる
      // （GA4 が欠けるだけでアプリは動くため）。Web の Google ログインは
      // ここに依存するので、設定漏れだと分かる形で止める。
      throw const AppFailure(
        FailureKind.unknown,
        'Google ログインは現在設定中です。メールアドレスでご登録ください。',
      );
    }
    return fb.FirebaseAuth.instance;
  }

  /// google_sign_in の初期化。プロセス内で 1 回だけ走らせる。
  ///
  /// v7 系の `initialize()` は 2 回目の呼び出しで StateError を投げるため、
  /// 完了フラグではなく Future 自体を共有し、同時に押されても 1 回に畳む。
  static Future<void>? _googleInitialization;

  /// テスト用。プロセス共有の初期化状態を捨てる。
  @visibleForTesting
  static void debugResetGoogleSignIn() => _googleInitialization = null;

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
