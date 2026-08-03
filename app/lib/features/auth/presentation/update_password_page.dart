import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';

/// 新しいパスワードの設定画面。
///
/// パスワード再設定メールのリンクを開くと復旧セッションでログインされ、
/// router が `AuthChangeEvent.passwordRecovery` を検知してこの画面を開く。
class UpdatePasswordPage extends ConsumerStatefulWidget {
  const UpdatePasswordPage({super.key});

  @override
  ConsumerState<UpdatePasswordPage> createState() => _UpdatePasswordPageState();
}

class _UpdatePasswordPageState extends ConsumerState<UpdatePasswordPage> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('パスワードを変更しました。')),
      );
      context.go(AppRoutes.campaignList);
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
      appBar: AppBar(title: const Text('新しいパスワードの設定')),
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
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const <String>[AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: '新しいパスワード',
                      helperText: '$MIN_PASSWORD_LENGTH 文字以上・英字と数字を含む',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordConfirm,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: '新しいパスワード（確認）'),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SubmitButton(
                    label: '変更する',
                    submitting: _submitting,
                    onPressed: _save,
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
