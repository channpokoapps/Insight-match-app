import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_callback_trace.dart';
import '../../../core/env/env.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/error_notice.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/auth_repository.dart';
import 'google_continue_button.dart';

/// ログイン画面。
///
/// メールアドレス + パスワード、または Google アカウントでログインする。
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _submitting = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await action();
    } on AppFailure catch (failure) {
      setState(() => _error = failure.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _signIn() => _run(() async {
        await ref
            .read(authRepositoryProvider)
            .signInWithPassword(_email.text, _password.text);
      });

  @override
  Widget build(BuildContext context) {
    // 確認メール・パスワード再設定メールのリンクからの復帰に失敗した場合、
    // この画面に戻されるだけで何のフィードバックも出ないため、
    // コールバックの失敗もここで表示する。
    final AppFailure? callbackFailure = ref.watch(authCallbackFailureProvider);
    final String? message = _error ?? callbackFailure?.message;
    final AuthCallbackTrace trace = ref.watch(authCallbackTraceProvider);

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
                  const Center(child: BrandMark()),
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
                  const SizedBox(height: 32),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'メールアドレス',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: !_showPassword,
                    autofillHints: const <String>[AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'パスワード',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        tooltip: _showPassword ? 'パスワードを隠す' : 'パスワードを表示',
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    onSubmitted: (_) => _submitting ? null : _signIn(),
                  ),
                  if (message != null) ...<Widget>[
                    const SizedBox(height: 12),
                    ErrorNotice(message: message),
                  ],
                  // 認証から戻ってきた形跡があるのに失敗している場合だけ、
                  // 切り分けに必要な最小限（戻り先ホストと理由）を出す。
                  // 認可コードの値そのものは含めない（AGENTS.md R-7）。
                  if (callbackFailure != null || trace.isCallback) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      trace.describe(),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SubmitButton(
                    label: 'ログイン',
                    submitting: _submitting,
                    onPressed: _signIn,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'または',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey.shade500),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 初回利用時は自動的にアカウント作成になる。
                  GoogleContinueButton(
                    enabled: !_submitting,
                    onBusyChanged: (bool busy) {
                      if (mounted) {
                        setState(() => _submitting = busy);
                      }
                    },
                    onFailure: (String message) {
                      if (mounted) {
                        setState(() => _error = message);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => context.push(AppRoutes.signUp),
                    child: const Text('はじめての方はアカウントを作成'),
                  ),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => context.push(AppRoutes.passwordReset),
                    child: const Text('パスワードを忘れた場合'),
                  ),
                  const SizedBox(height: 16),
                  // 「どのホストの、どのビルドを見ているか」を画面から判別できる
                  // ようにする。端末キャッシュやデプロイ漏れで古い版を見たまま
                  // 調査が空回りするのを防ぐ（PoC 期の運用都合）。
                  Text(
                    '${trace.host} · build ${Env.buildRev}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
