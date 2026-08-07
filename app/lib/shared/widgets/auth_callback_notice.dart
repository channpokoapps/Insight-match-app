import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_callback_trace.dart';
import '../../core/env/env.dart';
import '../../core/error/app_failure.dart';
import '../../features/auth/data/auth_repository.dart';
import 'error_notice.dart';

/// 認証コールバックの失敗と、切り分け用の起動情報を出す帯。
///
/// 確認メール・パスワード再設定メールのリンクは別ページから戻ってくるため、
/// 失敗しても押した本人には例外が返らない（アプリは起動し直している）。
/// 何も出さないと「リンクを開いたのに何も起きない」だけの状態になるので、
/// 未ログインの入口画面に必ずこれを置く。
class AuthCallbackNotice extends ConsumerWidget {
  const AuthCallbackNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppFailure? failure = ref.watch(authCallbackFailureProvider);
    final AuthCallbackTrace trace = ref.watch(authCallbackTraceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (failure != null) ...<Widget>[
          ErrorNotice(message: failure.message),
          const SizedBox(height: 8),
        ],
        // 認証から戻ってきた形跡があるのに失敗している場合だけ、切り分けに
        // 必要な最小限（戻り先ホストと理由）を出す。認可コードの値そのものは
        // 含めない（AGENTS.md R-7）。
        if (failure != null || trace.isCallback) ...<Widget>[
          Text(
            trace.describe(),
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
        // 「どのホストの、どのビルドを見ているか」を画面から判別できるように
        // する。端末キャッシュやデプロイ漏れで古い版を見たまま調査が空回りする
        // のを防ぐ（PoC 期の運用都合）。
        Text(
          '${trace.host} · build ${Env.buildRev}',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
