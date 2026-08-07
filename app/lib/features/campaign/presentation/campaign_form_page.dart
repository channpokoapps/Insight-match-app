import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/masters/master_repository.dart';
import '../../../core/platform/platform_capability.dart';
import '../../../shared/widgets/install_prompt.dart';
import '../../../shared/widgets/retry_notice.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/client_campaign_repository.dart';
import '../domain/campaign_draft.dart';
import '../domain/client_campaign.dart';
import '../../search/domain/criteria.dart';
import '../domain/criteria_editor.dart';
import 'criteria_builder.dart';
import 'criteria_template_sheet.dart';

/// 案件の作成・編集フォーム（PR依頼者向け）。
///
/// FR-CMP-01〜04 / 06〜13。[campaignId] が null なら新規作成。
/// 期間は「応募締切 → 訪問期間 → 報告期間」の 3 段階。
/// 応募が入ったあとは募集条件・人数・期間・投稿対象を編集できない
/// （FR-CMP-13。担保はサーバー側のトリガー、ここでは UI を無効化するだけ）。
class CampaignFormPage extends ConsumerStatefulWidget {
  const CampaignFormPage({this.campaignId, super.key});

  final String? campaignId;

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
  CriteriaEditor _criteria = CriteriaEditor();

  /// 新規作成時に貯める画像。案件 id が決まってからまとめて上げる。
  final List<CampaignImageData> _pendingImages = <CampaignImageData>[];

  /// 編集時にすでに保存されている画像のパス。
  List<String> _savedImagePaths = <String>[];

  int? _genreId;
  StoreDefaults? _defaults;
  bool _prefilled = false;
  bool _submitting = false;

  /// 応募が入っているため募集条件・人数・期間を変更できない状態。
  bool _locked = false;
  String? _error;

  late DateTime _applyEndDate;
  late DateTime _visitStartDate;
  late DateTime _visitEndDate;
  late DateTime _postStartDate;
  late DateTime _postEndDate;

  bool get _isEdit => widget.campaignId != null;

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
  ///
  /// 取得に失敗したあと再試行で届くこともあるため、
  /// すでに入力済みの内容は上書きしない。
  void _prefillFromStore(StoreDefaults defaults) {
    if (_prefilled) {
      return;
    }
    _prefilled = true;
    _defaults = defaults;
    if (_storeName.text.trim().isEmpty) {
      _storeName.text = defaults.storeName;
    }
    _genreId ??= defaults.genreId;
  }

  /// 編集対象の案件を、最初の 1 回だけフォームへ流し込む。
  void _prefillFromCampaign(EditableCampaign campaign) {
    if (_prefilled) {
      return;
    }
    _prefilled = true;
    final CampaignDraft d = campaign.draft;
    _title.text = d.title;
    _storeName.text = d.storeName;
    _rewardDescription.text = d.rewardDescription;
    _rewardValue.text = d.rewardValueJpy?.toString() ?? '';
    _quota.text = d.quota?.toString() ?? '';
    _requiredContent.text = d.requiredContent;
    _genreId = d.genreId;
    _platforms
      ..clear()
      ..addAll(d.platforms);
    _tags
      ..clear()
      ..addAll(d.hashtags);
    _applyEndDate = d.applyEndDate;
    _visitStartDate = d.visitStartDate;
    _visitEndDate = d.visitEndDate;
    _postStartDate = d.postStartDate;
    _postEndDate = d.postEndDate;
    _criteria = CriteriaEditor.fromCriteria(campaign.criteria);
    _savedImagePaths = List<String>.of(campaign.images);
    _locked = campaign.isLocked;
    _defaults = StoreDefaults(
      storeName: d.storeName,
      genreId: d.genreId,
      prefectureId: d.prefectureId,
      cityId: d.cityId,
      latitude: d.latitude,
      longitude: d.longitude,
      nearestStationId: d.nearestStationId,
    );
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
        criteria: _criteria.toCriteria(),
        prefectureId: _defaults?.prefectureId,
        cityId: _defaults?.cityId,
        latitude: _defaults?.latitude,
        longitude: _defaults?.longitude,
        nearestStationId: _defaults?.nearestStationId,
      );

  Future<void> _save({required bool publish}) async {
    final CampaignDraft draft = _buildDraft();
    final String? validationError =
        draft.validate() ?? _criteria.validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ClientCampaignRepository repository =
          ref.read(clientCampaignRepositoryProvider);
      if (_isEdit) {
        await repository.update(widget.campaignId!, draft);
        ref.invalidate(editableCampaignProvider(widget.campaignId!));
      } else {
        await repository.create(draft,
            publish: publish, images: _pendingImages);
      }
      ref.invalidate(ownCampaignsProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit
              ? '案件を更新しました。'
              : (publish ? '案件を公開しました。' : '下書きを保存しました。')),
        ),
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

  /// 保存した条件式を読み込む（FR-CMP-16）。いま組み立てている条件は置き換わる。
  Future<void> _applyTemplate() async {
    final Criteria? picked = await showCriteriaTemplateSheet(context, ref);
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _criteria = CriteriaEditor.fromCriteria(picked);
      _error = null;
    });
  }

  Future<void> _saveTemplate() async {
    final String? invalid = _criteria.validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final bool saved =
        await showSaveTemplateDialog(context, ref, _criteria.toCriteria());
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('条件をテンプレートとして保存しました。')),
      );
    }
  }

  Future<void> _pickImage() async {
    if (!ref
        .read(platformCapabilityProvider)
        .isAvailable(AppFeature.imageUpload)) {
      await showInstallPromptSheet(context, ref, AppFeature.imageUpload);
      return;
    }
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) {
      return;
    }
    final Uint8List bytes = await picked.readAsBytes();
    final CampaignImageData image = CampaignImageData(
      bytes: bytes,
      contentType: _contentTypeOf(picked.name),
    );
    if (!_isEdit) {
      setState(() => _pendingImages.add(image));
      return;
    }
    // 編集中は案件 id が決まっているので、その場で保存する。
    setState(() => _submitting = true);
    try {
      final String path = await ref
          .read(clientCampaignRepositoryProvider)
          .addImage(widget.campaignId!, image,
              sortOrder: _savedImagePaths.length);
      if (mounted) {
        setState(() => _savedImagePaths = <String>[..._savedImagePaths, path]);
      }
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

  Future<void> _removeSavedImage(String path) async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(clientCampaignRepositoryProvider)
          .removeImage(widget.campaignId!, path);
      if (mounted) {
        setState(() =>
            _savedImagePaths = _savedImagePaths.where((String p) => p != path).toList());
      }
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

  static String _contentTypeOf(String fileName) {
    final String lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
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
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '案件を編集' : '案件を作成')),
      body: _isEdit ? _buildEditBody() : _buildCreateBody(),
    );
  }

  Widget _buildCreateBody() {
    final AsyncValue<StoreDefaults> defaults = ref.watch(storeDefaultsProvider);
    return defaults.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // 店舗プロフィールの初期値は入力の手間を省くだけの機能（FR-CMP-02）。
      // 取れなくても案件は作成できるため、画面ごと止めずに注意書きを出す。
      error: (Object e, StackTrace _) => _buildForm(
        context,
        notice: _StoreDefaultsNotice(
          message: AppFailure.from(e).message,
          onRetry: () => ref.invalidate(storeDefaultsProvider),
        ),
      ),
      data: (StoreDefaults value) {
        _prefillFromStore(value);
        return _buildForm(context);
      },
    );
  }

  Widget _buildEditBody() {
    final AsyncValue<EditableCampaign> campaign =
        ref.watch(editableCampaignProvider(widget.campaignId!));
    return campaign.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) => RetryNotice(
        message: '案件を取得できませんでした。',
        onRetry: () =>
            ref.invalidate(editableCampaignProvider(widget.campaignId!)),
      ),
      data: (EditableCampaign value) {
        _prefillFromCampaign(value);
        return _buildForm(context);
      },
    );
  }

  Widget _buildForm(BuildContext context, {Widget? notice}) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<MasterItem>> genres = ref.watch(genresProvider);
    // 応募後は募集条件・人数・期間・投稿対象を触らせない（FR-CMP-13）。
    final bool termsEnabled = !_submitting && !_locked;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (notice != null) ...<Widget>[
                  notice,
                  const SizedBox(height: 16),
                ],
                if (_locked) ...<Widget>[
                  const _LockedNotice(),
                  const SizedBox(height: 16),
                ],
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
                        onSelected: termsEnabled
                            ? (bool selected) => setState(() {
                                  if (selected) {
                                    _platforms.add(platform);
                                  } else {
                                    _platforms.remove(platform);
                                  }
                                })
                            : null,
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
                const _SectionHeader(title: '画像'),
                _ImageSection(
                  pending: _pendingImages,
                  savedPaths: _savedImagePaths,
                  enabled: !_submitting,
                  onAdd: _pickImage,
                  onRemovePending: (int index) =>
                      setState(() => _pendingImages.removeAt(index)),
                  onRemoveSaved: _removeSavedImage,
                ),
                const SizedBox(height: 24),
                const _SectionHeader(title: '応募条件'),
                Text(
                  'インサイトの条件を設定すると、条件に合う投稿者にだけ案件の詳細が表示されます。'
                  '条件そのものは投稿者には見えません。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey.shade600, height: 1.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    TextButton.icon(
                      icon: const Icon(Icons.bookmark_border, size: 18),
                      label: const Text('保存した条件から選ぶ'),
                      onPressed: termsEnabled ? _applyTemplate : null,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('この条件を保存'),
                      onPressed: _submitting ? null : _saveTemplate,
                    ),
                  ],
                ),
                CriteriaBuilder(
                  editor: _criteria,
                  enabled: termsEnabled,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                MatchingCountBadge(editor: _criteria),
                const SizedBox(height: 24),
                const _SectionHeader(title: '募集要項'),
                TextField(
                  controller: _quota,
                  enabled: termsEnabled,
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
                  enabled: termsEnabled,
                  onTap: () => _pickDate(
                    current: _applyEndDate,
                    onPicked: (DateTime d) => _applyEndDate = d,
                  ),
                ),
                _DateTile(
                  label: '訪問期間（開始）',
                  value: _visitStartDate,
                  enabled: termsEnabled,
                  onTap: () => _pickDate(
                    current: _visitStartDate,
                    onPicked: (DateTime d) => _visitStartDate = d,
                  ),
                ),
                _DateTile(
                  label: '訪問期間（終了）',
                  value: _visitEndDate,
                  enabled: termsEnabled,
                  onTap: () => _pickDate(
                    current: _visitEndDate,
                    onPicked: (DateTime d) => _visitEndDate = d,
                  ),
                ),
                _DateTile(
                  label: '報告期間（開始）',
                  value: _postStartDate,
                  enabled: termsEnabled,
                  onTap: () => _pickDate(
                    current: _postStartDate,
                    onPicked: (DateTime d) => _postStartDate = d,
                  ),
                ),
                _DateTile(
                  label: '報告期間（終了）',
                  value: _postEndDate,
                  enabled: termsEnabled,
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
                  label: _isEdit ? '変更を保存' : '公開する',
                  submitting: _submitting,
                  onPressed: () => _save(publish: true),
                ),
                if (!_isEdit) ...<Widget>[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _submitting ? null : () => _save(publish: false),
                    child: const Text('下書きとして保存'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 店舗プロフィールの初期値を引けなかったときの案内。
///
/// 案件作成そのものは続けられることを明示する（止まっていると誤解させない）。
class _StoreDefaultsNotice extends StatelessWidget {
  const _StoreDefaultsNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline, size: 20, color: Colors.orange.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '店舗情報を自動入力できませんでした。$message'
                  ' 店舗名などを入力すれば、このまま案件を作成できます。',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('自動入力を再試行'),
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  const _LockedNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_outline, size: 20, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'すでに応募があるため、応募条件・募集人数・期間・投稿対象は変更できません。'
              'タイトルや提供内容などの案内文は変更できます。',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 画像の選択・削除（FR-CMP-11）。
///
/// 新規作成時は端末上に保持し、案件を保存した時点でまとめて上げる。
/// 編集時は選んだ時点で保存する（案件 id が決まっているため）。
class _ImageSection extends ConsumerWidget {
  const _ImageSection({
    required this.pending,
    required this.savedPaths,
    required this.enabled,
    required this.onAdd,
    required this.onRemovePending,
    required this.onRemoveSaved,
  });

  final List<CampaignImageData> pending;
  final List<String> savedPaths;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemovePending;
  final ValueChanged<String> onRemoveSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<String>>? urls = savedPaths.isEmpty
        ? null
        : ref.watch(campaignImageUrlsProvider(savedPaths.join(',')));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '店舗や提供内容の写真を追加できます（1枚あたり5MBまで）。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (int i = 0; i < savedPaths.length; i++)
                _Thumbnail(
                  // 署名付き URL は取得できるまで null。取得できなければ
                  // 破損ではなく「読み込めない」ことだけを示す。
                  imageUrl: urls?.valueOrNull != null &&
                          i < urls!.valueOrNull!.length
                      ? urls.valueOrNull![i]
                      : null,
                  onRemove: enabled ? () => onRemoveSaved(savedPaths[i]) : null,
                ),
              for (int i = 0; i < pending.length; i++)
                _Thumbnail(
                  bytes: pending[i].bytes,
                  onRemove: enabled ? () => onRemovePending(i) : null,
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  onPressed: enabled ? onAdd : null,
                  child: const SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.add_a_photo_outlined, size: 22),
                        SizedBox(height: 4),
                        Text('追加', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.imageUrl, this.bytes, this.onRemove});

  final String? imageUrl;
  final Uint8List? bytes;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 96,
              height: 96,
              child: bytes != null
                  ? Image.memory(bytes!, fit: BoxFit.cover)
                  : (imageUrl != null
                      ? Image.network(imageUrl!, fit: BoxFit.cover)
                      : Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image_outlined,
                              color: Colors.grey),
                        )),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
        ],
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
