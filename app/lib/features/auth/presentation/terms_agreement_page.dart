import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/profile_repository.dart';
import '../domain/app_role.dart';
import '../domain/consent_terms.dart';

/// 利用規約・プライバシーポリシーへの同意画面。
///
/// 表示する文言は役割によって変わる（`consentSectionsFor`）。
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
    // 役割選択の直後に表示される画面なので、登録フローが持つ役割を使う。
    // 取得前は投稿者向けの文言を出さず、共通部分だけが見えるよう creator に倒す。
    final AppRole role =
        ref.watch(registrationStepProvider).valueOrNull?.role ??
            ref.watch(myRoleProvider) ??
            AppRole.creator;
    final List<ConsentSection> sections = consentSectionsFor(role);
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
                  Text(
                    '${role.label}としてご利用にあたって',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final ConsentSection section in sections) ...<Widget>[
                    _ConsentCard(section: section),
                    const SizedBox(height: 12),
                  ],
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
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _checked,
                    onChanged: _submitting
                        ? null
                        : (bool? value) =>
                            setState(() => _checked = value ?? false),
                    title: Text(
                      '上記の免責事項を含む利用規約とプライバシーポリシー'
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
                  SubmitButton(
                    label: '同意して進む',
                    submitting: _submitting,
                    enabled: _checked,
                    onPressed: _agree,
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

/// 同意文言の 1 セクション。免責は読み飛ばされないよう配色で強調する。
class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.section});

  final ConsentSection section;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      color: section.isDisclaimer ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              section.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: section.isDisclaimer ? scheme.onErrorContainer : null,
                  ),
            ),
            const SizedBox(height: 8),
            for (final String bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '・$bullet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        color:
                            section.isDisclaimer ? scheme.onErrorContainer : null,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
