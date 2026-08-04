import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../shared/widgets/retry_notice.dart';
import '../../search/domain/criteria.dart';
import '../data/client_campaign_repository.dart';
import '../domain/criteria_template.dart';

/// 保存済みの条件テンプレートから選ぶ（FR-CMP-16）。
///
/// 選ばれたテンプレートの条件式を返す。選ばずに閉じたら null。
Future<Criteria?> showCriteriaTemplateSheet(
  BuildContext context,
  WidgetRef ref,
) =>
    showModalBottomSheet<Criteria>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _TemplateSheet(),
    );

/// 現在の条件式に名前を付けて保存する。保存したら true を返す。
Future<bool> showSaveTemplateDialog(
  BuildContext context,
  WidgetRef ref,
  Criteria criteria,
) async {
  final TextEditingController name = TextEditingController();
  String? error;
  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => AlertDialog(
        title: const Text('条件をテンプレートとして保存'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('次に案件を作るときに、同じ条件を呼び出せます。'),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'テンプレート名',
                hintText: '例: フォロワー1000人以上（関西）',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) {
                setState(() => error = 'テンプレート名を入力してください。');
                return;
              }
              try {
                await ref
                    .read(clientCampaignRepositoryProvider)
                    .saveTemplate(name.text, criteria);
                ref.invalidate(criteriaTemplatesProvider);
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              } on AppFailure catch (failure) {
                setState(() => error = failure.message);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  return saved ?? false;
}

class _TemplateSheet extends ConsumerWidget {
  const _TemplateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<CriteriaTemplate>> templates =
        ref.watch(criteriaTemplatesProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '保存した条件から選ぶ',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '選ぶと、いま入力している条件を置き換えます。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: templates.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object e, StackTrace _) => RetryNotice(
                  message: '保存した条件を取得できませんでした。',
                  onRetry: () => ref.invalidate(criteriaTemplatesProvider),
                ),
                data: (List<CriteriaTemplate> items) => items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'まだ保存した条件がありません。'
                          '条件を組み立てたあと「この条件を保存」から追加できます。',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade700),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) =>
                            _TemplateTile(template: items[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.template});

  final CriteriaTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(template.name),
      subtitle: Text(template.summary),
      trailing: IconButton(
        tooltip: 'このテンプレートを削除',
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () async {
          try {
            await ref
                .read(clientCampaignRepositoryProvider)
                .deleteTemplate(template.id);
            ref.invalidate(criteriaTemplatesProvider);
          } on AppFailure catch (failure) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(failure.message)),
              );
            }
          }
        },
      ),
      onTap: () => Navigator.of(context).pop(template.criteria),
    );
  }
}
