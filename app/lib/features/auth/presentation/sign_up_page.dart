import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../data/auth_repository.dart';

/// アカウント新規作成画面。
///
/// 登録後は確認メールのリンクを開いてもらう必要があるため、
/// 送信完了ビューに切り替えて案内する。既存メールアドレスでも
/// 同じ案内を出す（アカウント存在の推測を防ぐ）。
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();
  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'メールアドレスの形式が正しくありません。');
      return;
    }
    final String? passwordProblem = validatePassword(_password.text);
    if (passwordProblem != null) {
      setState(() => _error = passwordProblem);
      return;
    }
    if (_password.text != _passwordConfirm.text) {
      setState(() => _error = 'パスワード（確認）が一致しません。');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signUp(_email.text, _password.text);
      if (mounted) {
        setState(() => _sent = true);
      }
    } on AppFailure catch (failure) {
      setState(() => _error = failure.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新規登録')),
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
        const Icon(Icons.mark_email_read_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          '確認メールを送信しました',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'メール内のリンクを開くと登録が完了します。'
          '届かない場合は迷惑メールフォルダを確認してください。',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ログイン画面へ戻る'),
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
          decoration: const InputDecoration(labelText: 'メールアドレス'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const <String>[AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'パスワード',
            helperText: '$MIN_PASSWORD_LENGTH 文字以上・英字と数字を含む',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordConfirm,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'パスワード（確認）'),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _signUp,
          child: _submitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登録する'),
        ),
      ],
    );
  }
}
