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
  unknown,
}

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
    final String raw = error.toString();
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
    return const AppFailure(FailureKind.unknown, '処理に失敗しました。時間をおいて再度お試しください。');
  }

  @override
  String toString() => 'AppFailure($code)';
}
