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
/// 入力は SCR-CLI-03〜07 の 5 段階に分ける。1 画面に全項目を並べると
/// 縦に長くなり、公開ボタンまで何度もスクロールすることになるため。
/// 主要な操作（次へ・公開・保存）は常に画面下部に固定する。
///
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

  /// 表示中の入力段階。
  CampaignFormStep _step = CampaignFormStep.basics;

  /// 一度でも到達した最後の段階。ここまでは段階バーから直接戻れる。
  int _furthestStepIndex = 0;

  /// 応募が入っているため募集条件・人数・期間を変更できない状態。
  bool _locked = false;
  String? _error;

  /// 直前に判定した「破棄確認が要る状態か」。
  ///
  /// TextField への入力では再描画が起きないため、判定が変わった瞬間だけ
  /// 明示的に作り直して `PopScope` の可否を追従させる。
  bool _dirty = false;

  late DateTime _applyEndDate;
  late DateTime _visitStartDate;
  late DateTime _visitEndDate;
  late DateTime _postStartDate;
  late DateTime _postEndDate;

  bool get _isEdit => widget.campaignId != null;

  /// 破棄確認の要否を左右する自由入力欄。
  List<TextEditingController> get _dirtyWatched =>
      <TextEditingController>[_title, _rewardDescription, _requiredContent];

  @override
  void initState() {
    super.initState();
    final DateTime today = DateTime.now();
    _applyEndDate = today.add(const Duration(days: 7));
    _visitStartDate = today.add(const Duration(days: 8));
    _visitEndDate = today.add(const Duration(days: 14));
    _postStartDate = today.add(const Duration(days: 8));
    _postEndDate = today.add(const Duration(days: 21));
    for (final TextEditingController c in _dirtyWatched) {
      c.addListener(_syncDirty);
    }
  }

  void _syncDirty() {
    if (_dirty != _hasUnsavedInput) {
      setState(() => _dirty = _hasUnsavedInput);
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _dirtyWatched) {
      c.removeListener(_syncDirty);
    }
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
    // 編集は入力済みの案件を直すための画面なので、どの段階へも直接行ける。
    _furthestStepIndex = CampaignFormStep.values.length - 1;
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

  /// 表示中の段階の入力だけを検証する。問題がなければ null。
  String? _validateCurrentStep() => _step == CampaignFormStep.criteria
      ? _criteria.validate()
      : _buildDraft().validateStep(_step);

  void _goToStep(CampaignFormStep step) {
    setState(() {
      _step = step;
      _error = null;
      if (step.index > _furthestStepIndex) {
        _furthestStepIndex = step.index;
      }
    });
  }

  /// 次の段階へ進む。未入力があればそこで止めて理由を出す。
  void _goNext() {
    final String? invalid = _validateCurrentStep();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    _goToStep(_step.next);
  }

  Future<void> _save({required bool publish}) async {
    final CampaignDraft draft = _buildDraft();
    final String? validationError = draft.validate() ?? _criteria.validate();
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
        setState(() => _savedImagePaths =
            _savedImagePaths.where((String p) => p != path).toList());
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

  /// 破棄すると消えてしまう入力があるか。新規作成時の誤操作を防ぐ判定。
  bool get _hasUnsavedInput =>
      !_isEdit &&
      (_title.text.trim().isNotEmpty ||
          _rewardDescription.text.trim().isNotEmpty ||
          _requiredContent.text.trim().isNotEmpty ||
          _pendingImages.isNotEmpty ||
          _tags.isNotEmpty ||
          _criteria.completedLeafCount > 0);

  Future<bool> _confirmDiscard() async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('入力内容を破棄しますか？'),
        content: const Text('保存していない入力は失われます。'
            '残しておくなら「下書きとして保存」から保存できます。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('編集を続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('破棄する'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedInput,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final bool discard = await _confirmDiscard();
        if (!discard || !context.mounted) {
          return;
        }
        context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? '案件を編集' : '案件を作成'),
          actions: <Widget>[
            // 編集は 1 か所だけ直したい場面が多いので、最後まで進まなくても保存できる。
            if (_isEdit)
              TextButton(
                onPressed: _submitting ? null : () => _save(publish: true),
                child: const Text('保存'),
              ),
          ],
          bottom: _StepBar(
            current: _step,
            reachableIndex: _furthestStepIndex,
            onSelect: _submitting ? null : _goToStep,
          ),
        ),
        body: _isEdit ? _buildEditBody() : _buildCreateBody(),
      ),
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
    return SafeArea(
      child: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              // 段階を切り替えたら先頭から読ませる。
              key: ValueKey<String>('step-${_step.name}'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (notice != null &&
                          _step == CampaignFormStep.basics) ...<Widget>[
                        notice,
                        const SizedBox(height: 16),
                      ],
                      if (_locked &&
                          _step != CampaignFormStep.instructions) ...<Widget>[
                        const _LockedNotice(),
                        const SizedBox(height: 16),
                      ],
                      ..._buildStepChildren(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildActionBar(context),
        ],
      ),
    );
  }

  List<Widget> _buildStepChildren(BuildContext context) => switch (_step) {
        CampaignFormStep.basics => _basicsChildren(context),
        CampaignFormStep.criteria => _criteriaChildren(context),
        CampaignFormStep.terms => _termsChildren(context),
        CampaignFormStep.instructions => _instructionsChildren(context),
        CampaignFormStep.confirm => _confirmChildren(context),
      };

  // ---------------------------------------------------------------- ① 基本

  List<Widget> _basicsChildren(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<MasterItem>> genres = ref.watch(genresProvider);
    final bool termsEnabled = !_submitting && !_locked;
    return <Widget>[
      TextField(
        controller: _title,
        enabled: !_submitting,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '案件タイトル',
          helperText: '例: 新作ディナーコースを Instagram で紹介してください',
          helperMaxLines: 2,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: TextField(
              controller: _storeName,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: '店舗名',
                helperText: '店舗プロフィールから自動入力',
                helperMaxLines: 2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>('genre-$_genreId'),
              initialValue: _genreId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ジャンル'),
              items: <DropdownMenuItem<int>>[
                for (final MasterItem g in genres.valueOrNull ?? <MasterItem>[])
                  DropdownMenuItem<int>(value: g.id, child: Text(g.name)),
              ],
              onChanged: _submitting
                  ? null
                  : (int? value) => setState(() => _genreId = value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _FieldLabel(text: '投稿対象の SNS', style: theme.textTheme.titleSmall),
      Wrap(
        spacing: 8,
        children: <Widget>[
          for (final CampaignPlatform platform in CampaignPlatform.values)
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
      const SizedBox(height: 20),
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
      const SizedBox(height: 20),
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
    ];
  }

  // ---------------------------------------------------------------- ② 条件

  List<Widget> _criteriaChildren(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool termsEnabled = !_submitting && !_locked;
    return <Widget>[
      Text(
        'インサイトの条件を設定すると、条件に合う投稿者にだけ案件の詳細が表示されます。'
        '条件そのものは投稿者には見えません。条件なしのままでも公開できます。',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: Colors.grey.shade600, height: 1.5),
      ),
      const SizedBox(height: 8),
      // 幅の狭い端末では 2 行に折り返す（横に並べきれず切れるため）。
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        children: <Widget>[
          TextButton.icon(
            icon: const Icon(Icons.bookmark_border, size: 18),
            label: const Text('保存した条件から選ぶ'),
            onPressed: termsEnabled ? _applyTemplate : null,
          ),
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
    ];
  }

  // ---------------------------------------------------------------- ③ 要項

  List<Widget> _termsChildren(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool termsEnabled = !_submitting && !_locked;
    return <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
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
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _DateField(
              label: '応募締切日',
              value: _applyEndDate,
              enabled: termsEnabled,
              onTap: () => _pickDate(
                current: _applyEndDate,
                onPicked: (DateTime d) => _applyEndDate = d,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _FieldLabel(text: '訪問期間', style: theme.textTheme.titleSmall),
      _DateRangeRow(
        start: _visitStartDate,
        end: _visitEndDate,
        enabled: termsEnabled,
        onTapStart: () => _pickDate(
          current: _visitStartDate,
          onPicked: (DateTime d) => _visitStartDate = d,
        ),
        onTapEnd: () => _pickDate(
          current: _visitEndDate,
          onPicked: (DateTime d) => _visitEndDate = d,
        ),
      ),
      const SizedBox(height: 20),
      _FieldLabel(
        text: '報告期間（SNS への投稿・報告）',
        style: theme.textTheme.titleSmall,
      ),
      _DateRangeRow(
        start: _postStartDate,
        end: _postEndDate,
        enabled: termsEnabled,
        onTapStart: () => _pickDate(
          current: _postStartDate,
          onPicked: (DateTime d) => _postStartDate = d,
        ),
        onTapEnd: () => _pickDate(
          current: _postEndDate,
          onPicked: (DateTime d) => _postEndDate = d,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '応募締切のあとに訪問期間、訪問開始以降に報告期間を設定します。',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
      ),
    ];
  }

  // ---------------------------------------------------------------- ④ 指示

  List<Widget> _instructionsChildren(BuildContext context) {
    return <Widget>[
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
              onDeleted:
                  _submitting ? null : () => setState(() => _tags.remove(tag)),
            ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _requiredContent,
        enabled: !_submitting,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: '必須投稿内容',
          helperText: '訴求ポイント・必ず載せてほしい内容を記載します',
          helperMaxLines: 2,
          alignLabelWithHint: true,
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------- ⑤ 確認

  List<Widget> _confirmChildren(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CampaignDraft draft = _buildDraft();
    final String genreName =
        _genreNameOf(ref.watch(genresProvider).valueOrNull ?? <MasterItem>[]);
    final int imageCount = _pendingImages.length + _savedImagePaths.length;
    final int conditionCount = _criteria.completedLeafCount;
    return <Widget>[
      Text(
        _isEdit
            ? '変更した内容を確認してから保存してください。'
            : '内容を確認して公開します。公開後もタイトルや案内文は変更できます。',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: Colors.grey.shade600, height: 1.5),
      ),
      const SizedBox(height: 16),
      _SummaryCard(
        title: CampaignFormStep.basics.label,
        onEdit: () => _goToStep(CampaignFormStep.basics),
        rows: <_SummaryRow>[
          _SummaryRow('タイトル', draft.title.trim()),
          _SummaryRow('店舗名', draft.storeName.trim()),
          _SummaryRow('ジャンル', genreName),
          _SummaryRow(
            '投稿対象',
            _platforms.map((CampaignPlatform p) => p.label).join(' / '),
          ),
          _SummaryRow('提供内容', draft.rewardDescription.trim()),
          _SummaryRow('想定価格', '${draft.rewardValueJpy ?? 0} 円'),
          _SummaryRow('画像', '$imageCount 枚'),
        ],
      ),
      const SizedBox(height: 12),
      _SummaryCard(
        title: CampaignFormStep.criteria.label,
        onEdit: () => _goToStep(CampaignFormStep.criteria),
        rows: <_SummaryRow>[
          _SummaryRow(
            '条件',
            conditionCount == 0 ? '条件なし（全員が応募できます）' : '$conditionCount 件',
          ),
        ],
        // 条件に合う人数は k-匿名性で丸められることがある（実数を推定しない）。
        footer: conditionCount == 0
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MatchingCountBadge(editor: _criteria),
              ),
      ),
      const SizedBox(height: 12),
      _SummaryCard(
        title: CampaignFormStep.terms.label,
        onEdit: () => _goToStep(CampaignFormStep.terms),
        rows: <_SummaryRow>[
          _SummaryRow('募集人数', '${draft.quota ?? 0} 人'),
          _SummaryRow('応募締切', _formatDate(_applyEndDate)),
          _SummaryRow('訪問期間',
              '${_formatDate(_visitStartDate)} 〜 ${_formatDate(_visitEndDate)}'),
          _SummaryRow('報告期間',
              '${_formatDate(_postStartDate)} 〜 ${_formatDate(_postEndDate)}'),
        ],
      ),
      const SizedBox(height: 12),
      _SummaryCard(
        title: CampaignFormStep.instructions.label,
        onEdit: () => _goToStep(CampaignFormStep.instructions),
        rows: <_SummaryRow>[
          _SummaryRow(
            'ハッシュタグ',
            <String>[adDisclosureTag, ...draft.normalizedHashtags].join(' '),
          ),
          _SummaryRow('必須投稿内容', draft.requiredContent.trim()),
        ],
      ),
    ];
  }

  String _genreNameOf(List<MasterItem> genres) {
    for (final MasterItem g in genres) {
      if (g.id == _genreId) {
        return g.name;
      }
    }
    return '未選択';
  }

  static String _formatDate(DateTime value) =>
      '${value.year}/${value.month}/${value.day}';

  // ------------------------------------------------------------ 下部操作列

  /// 画面下に固定する操作列。
  ///
  /// スクロール位置に関わらず「次へ」「公開する」に届くようにする。
  /// エラーもここに出す（入力欄の近くだと画面外になることがあるため）。
  Widget _buildActionBar(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_error != null) ...<Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.error_outline,
                        size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: <Widget>[
                  if (!_step.isFirst) ...<Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => _goToStep(_step.previous),
                        child: const Text('戻る'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: _step.isLast
                        ? SubmitButton(
                            label: _isEdit ? '変更を保存' : '公開する',
                            submitting: _submitting,
                            onPressed: () => _save(publish: true),
                          )
                        : FilledButton(
                            onPressed: _submitting ? null : _goNext,
                            child: const Text('次へ'),
                          ),
                  ),
                ],
              ),
              if (_step.isLast && !_isEdit) ...<Widget>[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting ? null : () => _save(publish: false),
                  child: const Text('下書きとして保存'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 入力段階の進捗バー（SCR-CLI-03〜07）。
///
/// 到達済みの段階は押して戻れる。まだ通っていない段階は押せない
/// （順に入力してもらうため）。
class _StepBar extends StatelessWidget implements PreferredSizeWidget {
  const _StepBar({
    required this.current,
    required this.reachableIndex,
    required this.onSelect,
  });

  final CampaignFormStep current;

  /// 押して移動できる最後の段階の index。
  final int reachableIndex;

  final ValueChanged<CampaignFormStep>? onSelect;

  @override
  Size get preferredSize => const Size.fromHeight(54);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const List<CampaignFormStep> steps = CampaignFormStep.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final CampaignFormStep step in steps) ...<Widget>[
                if (step.index > 0) const SizedBox(width: 4),
                Expanded(
                  child: Semantics(
                    label: '${step.index + 1} ${step.label}',
                    selected: step == current,
                    child: GestureDetector(
                      onTap: onSelect == null || step.index > reachableIndex
                          ? null
                          : () => onSelect!(step),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: step.index <= current.index
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary
                                    .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${current.index + 1}. ${current.label}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${current.index + 1} / ${steps.length}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 確認段階に並べる 1 項目。
class _SummaryRow {
  const _SummaryRow(this.label, this.value);

  final String label;
  final String value;
}

/// 確認段階の 1 セクション。見出しから該当段階へ戻れる。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.onEdit,
    required this.rows,
    this.footer,
  });

  final String title;
  final VoidCallback onEdit;
  final List<_SummaryRow> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('修正'),
                  onPressed: onEdit,
                ),
              ],
            ),
            for (final _SummaryRow row in rows)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 96,
                      child: Text(
                        row.label,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.value.isEmpty ? '未入力' : row.value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: row.value.isEmpty
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (footer != null) footer!,
          ],
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
          style:
              theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
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
                  imageUrl:
                      urls?.valueOrNull != null && i < urls!.valueOrNull!.length
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

/// 入力欄ではないまとまり（チップ列・日付の組）に付ける見出し。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: style),
    );
  }
}

/// 日付 1 つ分の入力。テキスト入力欄と高さ・枠を揃える。
class _DateField extends StatelessWidget {
  const _DateField({
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
    return InkWell(
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: const Icon(Icons.event_outlined, size: 20),
        ),
        child: Text('${value.year}/${value.month}/${value.day}'),
      ),
    );
  }
}

/// 開始日と終了日を 1 行に並べる。縦の行数を半分にするための組。
class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow({
    required this.start,
    required this.end,
    required this.enabled,
    required this.onTapStart,
    required this.onTapEnd,
  });

  final DateTime start;
  final DateTime end;
  final bool enabled;
  final VoidCallback onTapStart;
  final VoidCallback onTapEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _DateField(
            label: '開始',
            value: start,
            enabled: enabled,
            onTap: onTapStart,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('〜'),
        ),
        Expanded(
          child: _DateField(
            label: '終了',
            value: end,
            enabled: enabled,
            onTap: onTapEnd,
          ),
        ),
      ],
    );
  }
}
