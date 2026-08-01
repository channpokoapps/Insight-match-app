/// Web 版の Firebase 接続設定を組み立てるファイル。
///
/// ネイティブ（Android）は `google-services.json` から初期化されるが、
/// Web にはその仕組みが無いため `FirebaseOptions` をコードで渡す必要がある。
///
/// `flutterfire configure` が生成する `firebase_options.dart` は資格情報を
/// 含むためリポジトリに登録しない方針であり、代わりにビルド時の
/// `--dart-define-from-file=env/web_firebase_config.json` で値を注入する。
/// これによりクリーンな clone でも `flutter analyze` / `flutter test` が通る。
library;

import 'package:firebase_core/firebase_core.dart';

const String _WEB_API_KEY = String.fromEnvironment('INSIGHT_MATCH_WEB_API_KEY');
const String _WEB_APP_ID = String.fromEnvironment('INSIGHT_MATCH_WEB_APP_ID');
const String _WEB_MESSAGING_SENDER_ID =
    String.fromEnvironment('INSIGHT_MATCH_WEB_MESSAGING_SENDER_ID');
const String _WEB_PROJECT_ID =
    String.fromEnvironment('INSIGHT_MATCH_WEB_PROJECT_ID');
const String _WEB_AUTH_DOMAIN =
    String.fromEnvironment('INSIGHT_MATCH_WEB_AUTH_DOMAIN');
const String _WEB_STORAGE_BUCKET =
    String.fromEnvironment('INSIGHT_MATCH_WEB_STORAGE_BUCKET');
const String _WEB_MEASUREMENT_ID =
    String.fromEnvironment('INSIGHT_MATCH_WEB_MEASUREMENT_ID');

/// Web 版の Firebase 設定が注入されているかどうか。
///
/// 未設定のままでも起動は継続する（GA4 計測が無効になるだけ）。
/// 本番ビルドでの設定漏れは `main.dart` が警告ログで知らせる。
bool hasWebFirebaseConfig({Map<String, String>? values}) {
  String read(String name, String fallback) =>
      values != null ? (values[name] ?? '') : fallback;
  return read('INSIGHT_MATCH_WEB_API_KEY', _WEB_API_KEY).isNotEmpty &&
      read('INSIGHT_MATCH_WEB_APP_ID', _WEB_APP_ID).isNotEmpty &&
      read('INSIGHT_MATCH_WEB_PROJECT_ID', _WEB_PROJECT_ID).isNotEmpty;
}

/// Web 版の Firebase 接続設定を組み立てる。
///
/// [values] テスト用の上書き値。キーはビルド時定義と同名。
/// 省略時はビルド時定義（`--dart-define-from-file`）から読み取る。
/// 必須値が欠けている場合は原因が分かる日本語の [StateError] を投げる。
FirebaseOptions buildWebFirebaseOptions({Map<String, String>? values}) {
  String read(String name, String fallback) =>
      values != null ? (values[name] ?? '') : fallback;

  final String apiKey = read('INSIGHT_MATCH_WEB_API_KEY', _WEB_API_KEY);
  final String appId = read('INSIGHT_MATCH_WEB_APP_ID', _WEB_APP_ID);
  final String messagingSenderId = read(
    'INSIGHT_MATCH_WEB_MESSAGING_SENDER_ID',
    _WEB_MESSAGING_SENDER_ID,
  );
  final String projectId =
      read('INSIGHT_MATCH_WEB_PROJECT_ID', _WEB_PROJECT_ID);
  final String authDomain =
      read('INSIGHT_MATCH_WEB_AUTH_DOMAIN', _WEB_AUTH_DOMAIN);
  final String storageBucket =
      read('INSIGHT_MATCH_WEB_STORAGE_BUCKET', _WEB_STORAGE_BUCKET);
  final String measurementId =
      read('INSIGHT_MATCH_WEB_MEASUREMENT_ID', _WEB_MEASUREMENT_ID);

  if (apiKey.isEmpty || appId.isEmpty || projectId.isEmpty) {
    throw StateError(
      'Web 版の Firebase 設定が不足しています。'
      '--dart-define-from-file=env/web_firebase_config.json を指定してください'
      '（docs/manual_setup/gcp_firebase.md 参照）。',
    );
  }

  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: authDomain.isEmpty ? null : authDomain,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
    measurementId: measurementId.isEmpty ? null : measurementId,
  );
}
