import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/auth_callback_notice.dart';

/// 認証ホーム画面（未ログイン時の入口）。
///
/// 入口を「新規アカウント作成」と「ログイン」の 2 つに分けて提示する。
/// いきなり入力フォームを見せるより初めての利用者が迷いにくいため、
/// 独立した画面として用意する（Shift Navi と同じ構成）。
class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: BrandMark(size: 72)),
                  const SizedBox(height: 16),
                  Text(
                    'SNS Insight Matcher',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'インサイトで選ぶ、数値は見せないマッチング',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  FilledButton(
                    onPressed: () => context.push(AppRoutes.signUp),
                    child: const Text('新規アカウント作成'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => context.push(AppRoutes.signIn),
                    child: const Text('ログイン'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'メールアドレスまたは Google アカウントで利用できます。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // メールリンクからの復帰に失敗した場合、この画面に着地する。
                  const AuthCallbackNotice(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
