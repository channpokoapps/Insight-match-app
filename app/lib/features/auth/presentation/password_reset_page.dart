import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';

/// パスワード再設定メールの送信画面。
///
/// メールアドレスの存在有無は画面に出さない（アカウント存在の推測を防ぐ）。
class PasswordResetPage extends ConsumerStatefulWidget {
  const PasswordResetPage({super.key});

  @override
  ConsumerState<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends ConsumerState<PasswordResetPage> {
  final TextEditingController _email = TextEditingController();
  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'メールアドレスの形式が正しくありません。');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(_email.text);
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
      appBar: AppBar(title: const Text('パスワード再設定')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _sent
                    ? <Widget>[
                        const Icon(Icons.mark_email_read_outlined, size: 56),
                        const SizedBox(height: 16),
                        Text(
                          '再設定メールを送信しました',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '登録済みのメールアドレスであれば、パスワード再設定の'
                          'リンクが届きます。リンクを開いて新しいパスワードを'
                          '設定してください。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('ログイン画面へ戻る'),
                        ),
                      ]
                    : <Widget>[
                        const Text(
                          '登録したメールアドレスを入力してください。'
                          'パスワード再設定用のリンクを送ります。',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const <String>[AutofillHints.email],
                          decoration:
                              const InputDecoration(labelText: 'メールアドレス'),
                          onSubmitted: (_) => _submitting ? null : _send(),
                        ),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SubmitButton(
                          label: '再設定メールを送る',
                          submitting: _submitting,
                          onPressed: _send,
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
