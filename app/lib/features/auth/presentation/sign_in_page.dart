import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/error_notice.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';

/// ログイン / 新規アカウント作成画面。
///
/// 認証ホーム画面（welcome_page.dart）から push され、入口ボタンに応じて
/// どちらのモードで開くかが決まる。モードは画面内のリンクで切り替えられる
/// （Shift Navi と同じ構成）。
///
/// メールアドレス + パスワード、または Google アカウントを使う。
/// 新規登録は確認メールのリンクを開いてもらう必要があるため、送信後は
/// 完了ビューに切り替えて案内する。既存メールアドレスでも同じ案内を出す
/// （アカウント存在の推測を防ぐ）。
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({this.initialSignUpMode = false, super.key});

  /// 新規アカウント作成モードで開くかどうか。
  final bool initialSignUpMode;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();

  late bool _signUpMode = widget.initialSignUpMode;
  bool _submitting = false;
  bool _showPassword = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
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
      if (mounted) {
        setState(() => _error = failure.message);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submit() {
    if (!_signUpMode) {
      return _run(() async {
        await ref
            .read(authRepositoryProvider)
            .signInWithPassword(_email.text, _password.text);
      });
    }
    final String? problem = _validateSignUp();
    if (problem != null) {
      setState(() => _error = problem);
      return Future<void>.value();
    }
    return _run(() async {
      await ref.read(authRepositoryProvider).signUp(_email.text, _password.text);
      if (mounted) {
        setState(() => _sent = true);
      }
    });
  }

  String? _validateSignUp() {
    if (!isValidEmail(_email.text)) {
      return 'メールアドレスの形式が正しくありません。';
    }
    final String? passwordProblem = validatePassword(_password.text);
    if (passwordProblem != null) {
      return passwordProblem;
    }
    if (_password.text != _passwordConfirm.text) {
      return 'パスワード（確認）が一致しません。';
    }
    return null;
  }

  /// Google アカウントでログインする。初回利用時は自動的にアカウント作成になる。
  ///
  /// 成功しても画面遷移はここでは行わない。セッションが張られると
  /// `onAuthStateChange` 経由で router が次の段階へ運ぶ（app_router.dart）。
  Future<void> _signInWithGoogle() => _run(() async {
        await ref.read(authRepositoryProvider).signInWithGoogle();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 認証ホーム画面から push されるため、戻る操作用の AppBar を置く。
      appBar: AppBar(title: Text(_signUpMode ? '新規アカウント作成' : 'ログイン')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _sent ? _buildSentView(context) : _buildForm(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSentView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.successGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 36,
            color: AppTheme.successGreen,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '確認メールを送信しました',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'メール内のリンクを開くと登録が完了します。'
          '届かない場合は迷惑メールフォルダを確認してください。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('戻る'),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
          autofillHints: <String>[
            _signUpMode ? AutofillHints.newPassword : AutofillHints.password,
          ],
          decoration: InputDecoration(
            labelText: 'パスワード',
            helperText:
                _signUpMode ? '$MIN_PASSWORD_LENGTH 文字以上・英字と数字を含む' : null,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              tooltip: _showPassword ? 'パスワードを隠す' : 'パスワードを表示',
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onSubmitted: (_) => _submitting ? null : _submit(),
        ),
        if (_signUpMode) ...<Widget>[
          const SizedBox(height: 12),
          TextField(
            controller: _passwordConfirm,
            obscureText: !_showPassword,
            decoration: const InputDecoration(
              labelText: 'パスワード（確認）',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          ErrorNotice(message: _error!),
        ],
        const SizedBox(height: 24),
        SubmitButton(
          label: _signUpMode ? 'アカウントを作成' : 'ログイン',
          submitting: _submitting,
          onPressed: _submit,
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
        // Google サインイン。初回利用時は自動的にアカウント作成になるため、
        // ログイン・新規作成のどちらのモードでも同じボタンを出す。
        OutlinedButton.icon(
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Google で続行'),
          onPressed: _submitting ? null : _signInWithGoogle,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _submitting
              ? null
              : () => setState(() {
                    _signUpMode = !_signUpMode;
                    _error = null;
                  }),
          child: Text(
            _signUpMode ? 'アカウントをお持ちの方はこちら' : 'はじめての方はアカウントを作成',
          ),
        ),
        if (!_signUpMode)
          TextButton(
            onPressed: _submitting
                ? null
                : () => context.push(AppRoutes.passwordReset),
            child: const Text('パスワードを忘れた場合'),
          ),
      ],
    );
  }
}
