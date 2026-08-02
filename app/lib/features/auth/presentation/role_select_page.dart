import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/error_notice.dart';
import '../data/auth_repository.dart';
import '../data/profile_repository.dart';
import '../domain/app_role.dart';

/// 役割（投稿者 / PR依頼者）の選択画面。初回登録フローの最初の段階。
///
/// 役割は後から変更できないため、それぞれの説明を添えて選ばせる。
class RoleSelectPage extends ConsumerStatefulWidget {
  const RoleSelectPage({super.key});

  @override
  ConsumerState<RoleSelectPage> createState() => _RoleSelectPageState();
}

class _RoleSelectPageState extends ConsumerState<RoleSelectPage> {
  bool _submitting = false;
  String? _error;

  Future<void> _select(AppRole role) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).createProfile(role);
      // router が次の段階（規約同意）へリダイレクトする。
      ref.invalidate(registrationStepProvider);
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
      appBar: AppBar(
        title: const Text('はじめる'),
        actions: <Widget>[
          TextButton(
            onPressed: _submitting
                ? null
                : () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('ログアウト'),
          ),
        ],
      ),
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
                    'どちらの立場で利用しますか？',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '選択した役割は後から変更できません。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _RoleCard(
                    leading: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.photo_camera_outlined,
                          color: Colors.white, size: 26),
                    ),
                    title: AppRole.creator.label,
                    description: 'SNS で投稿する側。Instagram を連携して、'
                        '条件に合う案件に応募します。インサイトの数値は'
                        '相手に公開されません。',
                    onTap: _submitting ? null : () => _select(AppRole.creator),
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    leading: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.successGreen.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.storefront_outlined,
                          color: AppTheme.successGreen, size: 26),
                    ),
                    title: AppRole.client.label,
                    description: '店舗・企業として PR を依頼する側。'
                        '案件を作成し、インサイト条件で投稿者を募集します。',
                    onTap: _submitting ? null : () => _select(AppRole.client),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    ErrorNotice(message: _error!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.leading,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              leading,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
