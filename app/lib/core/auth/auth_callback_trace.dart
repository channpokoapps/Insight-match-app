/// OAuth コールバックで「どこに」「何を持って」戻ってきたかの記録。
///
/// Web の OAuth は別ページへ遷移して戻るため、失敗しても呼び出し元に例外が
/// 返らない。しかも supabase_flutter は復帰直後に URL のパラメータを消す
/// (`clearAuthUrlParameters`)ので、後から調べる手段が残らない。
/// そこで `Supabase.initialize()` より前に一度だけ URL を捕まえておく。
///
/// 認可コード（`code`）そのものは記録しない。短命とはいえセッションと
/// 交換できる値であり、画面にもログにも出してはならない（AGENTS.md R-7）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 起動時に捕まえたコールバックの痕跡。`main()` で override して渡す。
final Provider<AuthCallbackTrace> authCallbackTraceProvider =
    Provider<AuthCallbackTrace>(
  (Ref ref) => throw UnimplementedError(
    'main() で overrideWithValue すること',
  ),
);

/// 起動時 URL に残っていたコールバックの痕跡。
class AuthCallbackTrace {
  const AuthCallbackTrace({
    required this.origin,
    required this.hasCode,
    this.error,
    this.errorDescription,
  });

  /// 認証を「開始した」オリジンとは限らない。Supabase の Redirect URLs に
  /// 一致しない `redirect_to` は Site URL に差し替えられて戻されるため、
  /// ここが想定と違えば、その差し替えが起きたことを意味する。
  final String origin;

  /// 認可コードが付いていたか（値は保持しない）。
  final bool hasCode;

  /// `error` / `error_code` パラメータ。
  final String? error;

  /// `error_description` パラメータ。
  final String? errorDescription;

  /// 認証からの復帰であることが URL から判別できるか。
  bool get isCallback => hasCode || error != null;

  /// 表示用のホスト名。
  String get host => origin.isEmpty ? '-' : Uri.parse(origin).host;

  /// 起動時の URL から痕跡を取り出す。
  ///
  /// [uri] 省略時は `Uri.base`（Web では現在の URL）。
  factory AuthCallbackTrace.capture([Uri? uri]) {
    final Uri base = uri ?? Uri.base;
    // 実装によっては fragment 側に付く（implicit フロー）。両方見る。
    final Map<String, String> fragment = base.fragment.contains('=')
        ? Uri.splitQueryString(base.fragment)
        : const <String, String>{};
    String? pick(String key) =>
        base.queryParameters[key] ?? fragment[key];

    // `Uri.origin` は http(s) 以外や authority 無しで例外を投げる。
    // ここは main() の最初に通るので、投げると起動そのものが死ぬ
    // （Android の `Uri.base` は file:/// になる）。
    final bool hasHttpOrigin = base.hasAuthority &&
        (base.scheme == 'http' || base.scheme == 'https');

    return AuthCallbackTrace(
      origin: hasHttpOrigin ? base.origin : '',
      hasCode: pick('code') != null || pick('access_token') != null,
      error: pick('error') ?? pick('error_code'),
      errorDescription: pick('error_description'),
    );
  }

  /// 画面に出してよい一行の要約。原因の切り分けだけに使う。
  String describe() {
    final StringBuffer buffer = StringBuffer(origin.isEmpty ? '-' : origin);
    if (error != null) {
      buffer.write(' / $error');
      final String? detail = errorDescription;
      if (detail != null && detail.isNotEmpty) {
        buffer.write(': $detail');
      }
    } else if (hasCode) {
      buffer.write(' / 認可コードは受信済み');
    } else {
      buffer.write(' / 認証情報なし');
    }
    return buffer.toString();
  }
}
