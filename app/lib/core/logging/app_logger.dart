import 'package:logger/logger.dart';

/// アプリ共通のロガー。
///
/// インサイト実数値・アクセストークン・個人情報をログに出さない（AGENTS.md R-7）。
/// そのため任意のオブジェクトをそのまま渡せる API はあえて用意していない。
/// 出力してよいのは「識別子」と「イベント名」と「エラーコード」だけ。
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(methodCount: 0, errorMethodCount: 5),
  );

  /// ログに出してよいキーのホワイトリスト。
  static const Set<String> _allowedKeys = {
    'event',
    'screen',
    'campaign_id',
    'application_id',
    'room_id',
    'platform',
    'status',
    'error_code',
    'duration_ms',
    'count',
  };

  static void info(String event, [Map<String, Object?> fields = const {}]) {
    _logger.i('$event ${_sanitize(fields)}');
  }

  static void warn(String event, [Map<String, Object?> fields = const {}]) {
    _logger.w('$event ${_sanitize(fields)}');
  }

  /// エラーオブジェクトの本文にはトークンや個人情報が含まれうるため、
  /// メッセージそのものは出力せず、分類したコードのみを記録する。
  static void error(String event, String errorCode, [StackTrace? stackTrace]) {
    _logger.e('$event {error_code: $errorCode}', stackTrace: stackTrace);
  }

  static Map<String, Object?> _sanitize(Map<String, Object?> fields) {
    final Map<String, Object?> result = <String, Object?>{};
    fields.forEach((String key, Object? value) {
      if (_allowedKeys.contains(key)) {
        result[key] = value;
      }
    });
    return result;
  }
}
