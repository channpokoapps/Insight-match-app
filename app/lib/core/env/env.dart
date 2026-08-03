/// アプリの環境設定。
///
/// 値は `--dart-define-from-file=env/local.json` で注入する。
/// service_role キーは絶対にここへ入れない（AGENTS.md R-6）。
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// anon キーのみを保持する。RLS と RPC が権限を担保する前提。
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// GCP の「ウェブ アプリケーション」OAuth クライアント ID。
  ///
  /// Android の Google サインインで `serverClientId` として使う
  /// （docs/manual_setup/supabase.md §4.2）。未設定の間は
  /// Google サインインボタンがエラーメッセージを表示する。
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static const bool isProduction = bool.fromEnvironment('IS_PRODUCTION');

  /// ビルド元のコミット（CI が `--dart-define=BUILD_REV=<sha>` で埋める）。
  ///
  /// 端末のキャッシュやプレビューの更新漏れで「直したはずの版が動いていない」
  /// ことに気づけず調査が空回りするため、画面から判別できるようにする。
  static const String buildRev = String.fromEnvironment(
    'BUILD_REV',
    defaultValue: 'dev',
  );

  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_ANON_KEY が未設定です。'
        '--dart-define-from-file を指定して起動してください。',
      );
    }
  }
}
