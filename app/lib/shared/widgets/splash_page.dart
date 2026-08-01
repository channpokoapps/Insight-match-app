import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/profile_repository.dart';
import '../../features/auth/domain/registration_step.dart';

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
                  const Text('通信に失敗しました。'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.invalidate(registrationStepProvider),
                    child: const Text('再試行'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
