/// autoDispose な Provider の中で使うデバウンス。
///
/// 入力のたびにサーバへ問い合わせると、条件ビルダーのような
/// 「1 文字打つたびに再取得」する画面で無駄な往復が生まれる。
/// Provider が破棄された（＝より新しい入力が来た）時点で待機を
/// 打ち切り、後続の問い合わせ自体を行わせない。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 破棄済みの Provider で待機が中断されたことを表す。
///
/// 呼び出し側に届く前に Provider ごと捨てられるため、画面には出ない。
class DebounceCancelled implements Exception {
  const DebounceCancelled();

  @override
  String toString() => 'DebounceCancelled';
}

/// [duration] 待つ。待機中に Provider が破棄されたら [DebounceCancelled] を投げる。
Future<void> debounce(Ref ref, Duration duration) {
  final Completer<void> completer = Completer<void>();
  final Timer timer = Timer(duration, () {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  ref.onDispose(() {
    timer.cancel();
    if (!completer.isCompleted) {
      completer.completeError(const DebounceCancelled());
    }
  });
  return completer.future;
}
