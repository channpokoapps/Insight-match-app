import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../data/profile_repository.dart';

/// 利用規約・プライバシーポリシーへの同意画面。
///
/// 規約バージョン（`AppConfig.termsVersion`）を記録するため、
/// 改定時は再度この画面が表示される。
class TermsAgreementPage extends ConsumerStatefulWidget {
  const TermsAgreementPage({super.key});

  @override
  ConsumerState<TermsAgreementPage> createState() => _TermsAgreementPageState();
}

class _TermsAgreementPageState extends ConsumerState<TermsAgreementPage> {
  bool _checked = false;
  bool _submitting = false;
  String? _error;

  Future<void> _agree() async {
    final AppConfig config = ref.read(appConfigProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).agreeTo(config.termsVersion);
      ref.invalidate(registrationStepProvider);
    } on AppFailure catch (failure) {
      setState(() => _error = failure.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('規約ページは準備中です。')),
      );
      return;
    }
    await launchUrl(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final AppConfig config = ref.watch(appConfigProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('利用規約への同意')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'ご利用にあたって',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '・インサイトの実数値は、条件の判定にのみ使われ、'
                            '相手や運営を含む誰にも表示されません。\n'
                            '・PR 投稿には #PR の明示が必要です'
                            '（ステルスマーケティング規制対応）。\n'
                            '・詳細は利用規約とプライバシーポリシーを'
                            'ご確認ください。',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: <Widget>[
                              TextButton(
                                onPressed: () => _openUrl(config.termsUrl),
                                child: const Text('利用規約'),
                              ),
                              TextButton(
                                onPressed: () => _openUrl(config.privacyUrl),
                                child: const Text('プライバシーポリシー'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _checked,
                    onChanged: _submitting
                        ? null
                        : (bool? value) =>
                            setState(() => _checked = value ?? false),
                    title: Text(
                      '利用規約とプライバシーポリシー'
                      '（バージョン ${config.termsVersion}）に同意します',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _checked && !_submitting ? _agree : null,
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('同意して進む'),
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
