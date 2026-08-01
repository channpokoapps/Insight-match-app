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

/// パスワードの最小文字数。Supabase の既定（6 文字）より厳しくする。
const int MIN_PASSWORD_LENGTH = 8;

/// メールアドレスの形式を検証する。
///
/// 厳密な RFC 準拠ではなく、明らかな誤入力を弾くことを目的とする。
/// 最終的な妥当性は Supabase 側の検証に委ねる。
bool isValidEmail(String email) {
  final String trimmed = email.trim();
  if (trimmed.isEmpty || trimmed.length > 254 || trimmed.contains(' ')) {
    return false;
  }
  return RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$').hasMatch(trimmed);
}

/// パスワードの強度を検証する。
///
/// 戻り値は妥当なら null、問題があれば利用者向けの説明文。
String? validatePassword(String password) {
  if (password.length < MIN_PASSWORD_LENGTH) {
    return 'パスワードは $MIN_PASSWORD_LENGTH 文字以上で入力してください。';
  }
  final bool hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
  final bool hasDigit = RegExp(r'[0-9]').hasMatch(password);
  if (!hasLetter || !hasDigit) {
    return 'パスワードには英字と数字を両方含めてください。';
  }
  return null;
}

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
      await _client.auth.signUp(email: email.trim(), password: password);
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
      await _client.auth.resetPasswordForEmail(email.trim());
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
          redirectTo: Uri.base.origin,
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
