import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/masters/master_repository.dart';
import '../../../shared/widgets/retry_notice.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/client_campaign_repository.dart';
import '../domain/campaign_draft.dart';

/// 案件作成フォーム（PR依頼者向け、FR-CMP-01〜03 / 06〜10 / 12）。
///
/// 期間は「応募締切 → 訪問期間 → 報告期間」の 3 段階。
/// インサイト条件の設定（条件ビルダー）と画像は別画面で対応する（T-111 / T-113）。
class CampaignFormPage extends ConsumerStatefulWidget {
  const CampaignFormPage({super.key});

  @override
  ConsumerState<CampaignFormPage> createState() => _CampaignFormPageState();
}

class _CampaignFormPageState extends ConsumerState<CampaignFormPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _storeName = TextEditingController();
  final TextEditingController _rewardDescription = TextEditingController();
  final TextEditingController _rewardValue = TextEditingController();
  final TextEditingController _quota = TextEditingController(text: '1');
  final TextEditingController _hashtagInput = TextEditingController();
  final TextEditingController _requiredContent = TextEditingController();

  final Set<CampaignPlatform> _platforms = <CampaignPlatform>{
    CampaignPlatform.instagram,
  };
  final List<String> _tags = <String>[];
  int? _genreId;
  StoreDefaults? _defaults;
  bool _prefilled = false;
  bool _submitting = false;
  String? _error;

  late DateTime _applyEndDate;
  late DateTime _visitStartDate;
  late DateTime _visitEndDate;
  late DateTime _postStartDate;
  late DateTime _postEndDate;

  @override
  void initState() {
    super.initState();
    final DateTime today = DateTime.now();
    _applyEndDate = today.add(const Duration(days: 7));
    _visitStartDate = today.add(const Duration(days: 8));
    _visitEndDate = today.add(const Duration(days: 14));
    _postStartDate = today.add(const Duration(days: 8));
    _postEndDate = today.add(const Duration(days: 21));
  }

  @override
  void dispose() {
    _title.dispose();
    _storeName.dispose();
    _rewardDescription.dispose();
    _rewardValue.dispose();
    _quota.dispose();
    _hashtagInput.dispose();
    _requiredContent.dispose();
    super.dispose();
  }

  /// 店舗プロフィールからの初期値を、最初の 1 回だけ反映する。
  void _prefill(StoreDefaults defaults) {
    if (_prefilled) {
      return;
    }
    _prefilled = true;
    _defaults = defaults;
    _storeName.text = defaults.storeName;
    _genreId = defaults.genreId;
  }

  CampaignDraft _buildDraft() => CampaignDraft(
        title: _title.text,
        storeName: _storeName.text,
        platforms: Set<CampaignPlatform>.of(_platforms),
        rewardDescription: _rewardDescription.text,
        rewardValueJpy: int.tryParse(_rewardValue.text.trim()),
        quota: int.tryParse(_quota.text.trim()),
        applyEndDate: _applyEndDate,
        visitStartDate: _visitStartDate,
        visitEndDate: _visitEndDate,
        postStartDate: _postStartDate,
        postEndDate: _postEndDate,
        requiredContent: _requiredContent.text,
        genreId: _genreId,
        hashtags: List<String>.of(_tags),
        prefectureId: _defaults?.prefectureId,
        cityId: _defaults?.cityId,
        latitude: _defaults?.latitude,
        longitude: _defaults?.longitude,
        nearestStationId: _defaults?.nearestStationId,
      );

  Future<void> _save({required bool publish}) async {
    final CampaignDraft draft = _buildDraft();
    final String? validationError = draft.validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(clientCampaignRepositoryProvider)
          .create(draft, publish: publish);
      ref.invalidate(ownCampaignsProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(publish ? '案件を公開しました。' : '下書きを保存しました。')),
      );
      context.pop();
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

  void _addTag() {
    final String raw = _hashtagInput.text.trim();
    if (raw.isEmpty) {
      return;
    }
    final String tag = raw.startsWith('#') ? raw : '#$raw';
    setState(() {
      if (tag.toUpperCase() != adDisclosureTag && !_tags.contains(tag)) {
        _tags.add(tag);
      }
      _hashtagInput.clear();
    });
  }

  Future<void> _pickDate({
    required DateTime current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final DateTime today = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(today) ? today : current,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => onPicked(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<StoreDefaults> defaults =
        ref.watch(storeDefaultsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('案件を作成')),
      body: defaults.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => RetryNotice(
          message: '店舗情報を取得できませんでした。',
          onRetry: () => ref.invalidate(storeDefaultsProvider),
        ),
        data: (StoreDefaults value) {
          _prefill(value);
          return _buildForm(context);
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<MasterItem>> genres = ref.watch(genresProvider);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _SectionHeader(title: '基本情報'),
                TextField(
                  controller: _title,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: '案件タイトル',
                    helperText: '例: 新作ディナーコースを Instagram で紹介してください',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _storeName,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: '店舗名',
                    helperText: '店舗プロフィールから自動入力されます',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('genre-$_genreId'),
                  initialValue: _genreId,
                  decoration: const InputDecoration(labelText: 'ジャンル'),
                  items: <DropdownMenuItem<int>>[
                    for (final MasterItem g
                        in genres.valueOrNull ?? <MasterItem>[])
                      DropdownMenuItem<int>(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: _submitting
                      ? null
                      : (int? value) => setState(() => _genreId = value),
                ),
                const SizedBox(height: 16),
                Text('投稿対象の SNS', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final CampaignPlatform platform
                        in CampaignPlatform.values)
                      FilterChip(
                        label: Text(platform.label),
                        selected: _platforms.contains(platform),
                        onSelected: _submitting
                            ? null
                            : (bool selected) => setState(() {
                                  if (selected) {
                                    _platforms.add(platform);
                                  } else {
                                    _platforms.remove(platform);
                                  }
                                }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const _SectionHeader(title: '提供内容（無償提供）'),
                TextField(
                  controller: _rewardDescription,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '提供する商品・サービス',
                    helperText: '例: コース料理+ドリンク 1名分',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _rewardValue,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: '想定価格（円）',
                    helperText: '投稿者向けの一覧の並び順・絞り込みに使われます',
                    helperMaxLines: 2,
                    suffixText: '円',
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionHeader(title: '募集要項'),
                TextField(
                  controller: _quota,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: '募集人数',
                    suffixText: '人',
                  ),
                ),
                const SizedBox(height: 8),
                _DateTile(
                  label: '応募締切日',
                  value: _applyEndDate,
                  enabled: !_submitting,
                  onTap: () => _pickDate(
                    current: _applyEndDate,
                    onPicked: (DateTime d) => _applyEndDate = d,
                  ),
                ),
                _DateTile(
                  label: '訪問期間（開始）',
                  value: _visitStartDate,
                  enabled: !_submitting,
                  onTap: () => _pickDate(
                    current: _visitStartDate,
                    onPicked: (DateTime d) => _visitStartDate = d,
                  ),
                ),
                _DateTile(
                  label: '訪問期間（終了）',
                  value: _visitEndDate,
                  enabled: !_submitting,
                  onTap: () => _pickDate(
                    current: _visitEndDate,
                    onPicked: (DateTime d) => _visitEndDate = d,
                  ),
                ),
                _DateTile(
                  label: '報告期間（開始）',
                  value: _postStartDate,
                  enabled: !_submitting,
                  onTap: () => _pickDate(
                    current: _postStartDate,
                    onPicked: (DateTime d) => _postStartDate = d,
                  ),
                ),
                _DateTile(
                  label: '報告期間（終了）',
                  value: _postEndDate,
                  enabled: !_submitting,
                  onTap: () => _pickDate(
                    current: _postEndDate,
                    onPicked: (DateTime d) => _postEndDate = d,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '応募締切のあとに訪問期間、訪問開始以降に報告期間（SNS への投稿・報告）を設定します。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                const _SectionHeader(title: '投稿の指示'),
                TextField(
                  controller: _hashtagInput,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    labelText: '指定ハッシュタグを追加',
                    helperText: '広告表記タグ #PR は自動で付与され、削除できません',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _submitting ? null : _addTag,
                    ),
                  ),
                  onSubmitted: (_) => _addTag(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    // ステマ規制対応の広告表記タグ。外せないことを UI でも示す。
                    const Chip(
                      label: Text(adDisclosureTag),
                      avatar: Icon(Icons.lock_outline, size: 16),
                    ),
                    for (final String tag in _tags)
                      Chip(
                        label: Text(tag),
                        onDeleted: _submitting
                            ? null
                            : () => setState(() => _tags.remove(tag)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _requiredContent,
                  enabled: !_submitting,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '必須投稿内容',
                    helperText: '訴求ポイント・必ず載せてほしい内容を記載します',
                    helperMaxLines: 2,
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                SubmitButton(
                  label: '公開する',
                  submitting: _submitting,
                  onPressed: () => _save(publish: true),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _submitting ? null : () => _save(publish: false),
                  child: const Text('下書きとして保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(label),
      trailing: Text(
        '${value.year}/${value.month}/${value.day}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
