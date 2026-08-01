/// アプリの環境設定。
///
/// 値は `--dart-define-from-file=env/local.json` で注入する。
/// service_role キーは絶対にここへ入れない（AGENTS.md R-6）。
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// anon キーのみを保持する。RLS と RPC が権限を担保する前提。
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const bool isProduction = bool.fromEnvironment('IS_PRODUCTION');

  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_ANON_KEY が未設定です。'
        '--dart-define-from-file を指定して起動してください。',
      );
    }
  }
}
