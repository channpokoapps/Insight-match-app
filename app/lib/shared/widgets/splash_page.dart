import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/profile_repository.dart';
import '../../features/auth/domain/registration_step.dart';
import 'retry_notice.dart';

/// 起動直後・登録段階の判定中に表示するスプラッシュ画面。
///
/// 判定（`registrationStepProvider`）が失敗すると router はこの画面に
/// 留め続けるため、再試行の導線をここに持たせる。
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RegistrationState?> registration =
        ref.watch(registrationStepProvider);
    return Scaffold(
      body: Center(
        child: registration.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RetryNotice(
                    message: '通信に失敗しました。',
                    buttonLabel: '再試行',
                    onRetry: () => ref.invalidate(registrationStepProvider),
                  ),
                  // 再試行しても直らない場合にこの画面へ閉じ込められないための脱出導線。
                  // ログアウトすると router の認証ゲートがログイン画面へ戻す。
                  TextButton(
                    onPressed: () async {
                      try {
                        await ref.read(authRepositoryProvider).signOut();
                      } on Object {
                        // 失敗してもここでは案内できることがない。再試行に任せる。
                      }
                    },
                    child: const Text('ログアウトしてやり直す'),
                  ),
                ],
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  BrandMark(size: 88),
                  SizedBox(height: 32),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ],
              ),
      ),
    );
  }
}
