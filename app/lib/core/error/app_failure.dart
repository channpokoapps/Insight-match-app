import 'package:supabase_flutter/supabase_flutter.dart';

/// アプリ内で扱う失敗の分類。
///
/// サーバから返る例外メッセージには内部状態が含まれうるため、
/// 画面に出す文言はここで定義した安全なものだけを使う。
enum FailureKind {
  network,
  unauthorized,
  notEligible,
  alreadyApplied,
  notFound,
  conflict,

  /// アプリが要求するテーブル・列・関数が本番 DB に無い状態。
  /// マイグレーションの反映漏れ（docs/poc_guide.md §3）で起きる。
  serverOutdated,
  unknown,
}

/// マイグレーション未反映を示す SQLSTATE / PostgREST のコード。
///
/// 42703 = 列が無い / 42P01 = テーブルが無い / 42883 = 関数が無い。
/// PGRST2xx は PostgREST のスキーマキャッシュに無い場合。
const Set<String> _outdatedCodes = <String>{
  '42703',
  '42P01',
  '42883',
  'PGRST202',
  'PGRST204',
  'PGRST205',
};

class AppFailure implements Exception {
  const AppFailure(this.kind, this.message);

  final FailureKind kind;

  /// 利用者に表示してよい文言のみを入れる。
  final String message;

  /// ログに残してよい短いコード。
  String get code => kind.name;

  /// Supabase / PostgREST の例外を安全な失敗に変換する。
  ///
  /// 応募条件を満たさない場合、**どの条件で落ちたかは表示しない**。
  /// 理由を細かく返すとインサイト値の推測材料になるため（AGENTS.md R-1）。
  factory AppFailure.from(Object error) {
    // 変換済みのものを再変換して unknown に潰さない。
    if (error is AppFailure) {
      return error;
    }
    final String raw = error.toString();
    if (error is PostgrestException && _outdatedCodes.contains(error.code)) {
      return _serverOutdated;
    }
    if (raw.contains('応募条件を満たしていません')) {
      return const AppFailure(
        FailureKind.notEligible,
        'この案件の応募条件を満たしていません。',
      );
    }
    if (raw.contains('すでに応募済みです')) {
      return const AppFailure(FailureKind.alreadyApplied, 'すでに応募済みです。');
    }
    if (raw.contains('unauthorized')) {
      return const AppFailure(FailureKind.unauthorized, 'この操作を行う権限がありません。');
    }
    if (raw.contains('not found')) {
      return const AppFailure(FailureKind.notFound, '対象が見つかりませんでした。');
    }
    if (raw.contains('SocketException') || raw.contains('ClientException')) {
      return const AppFailure(FailureKind.network, '通信に失敗しました。電波状況を確認してください。');
    }
    // 型が落ちて素の Exception で届く経路（RPC 内の raise など）の保険。
    if (raw.contains('does not exist') ||
        raw.contains('schema cache') ||
        raw.contains('Could not find the')) {
      return _serverOutdated;
    }
    return const AppFailure(FailureKind.unknown, '処理に失敗しました。時間をおいて再度お試しください。');
  }

  /// サーバー側（DB）の更新が未反映であることを、次の行動つきで伝える。
  static const AppFailure _serverOutdated = AppFailure(
    FailureKind.serverOutdated,
    'アプリの更新がサーバー側にまだ反映されていません。'
    '運営者は GitHub の「Supabase マイグレーション反映」を実行してください。',
  );

  @override
  String toString() => 'AppFailure($code)';
}
