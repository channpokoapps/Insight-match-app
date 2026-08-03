import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/masters/master_repository.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/profile_repository.dart';
import '../domain/auth_validators.dart';

/// 投稿者（creator）のプロフィール登録画面。
///
/// 18 歳未満は登録できない（OI-08、判定は [isOldEnough]）。氏名・生年月日は
/// 本人確認と年齢判定のためだけに使い、PR依頼者には一切表示されない
/// （AGENTS.md R-5）。
class CreatorProfileFormPage extends ConsumerStatefulWidget {
  const CreatorProfileFormPage({super.key});

  @override
  ConsumerState<CreatorProfileFormPage> createState() =>
      _CreatorProfileFormPageState();
}

class _CreatorProfileFormPageState
    extends ConsumerState<CreatorProfileFormPage> {
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  DateTime? _birthDate;
  int? _prefectureId;
  final Set<int> _genreIds = <int>{};
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      locale: const Locale('ja'),
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _save() async {
    final String fullName = _fullName.text.trim();
    if (fullName.isEmpty) {
      setState(() => _error = '氏名を入力してください。');
      return;
    }
    final DateTime? birthDate = _birthDate;
    if (birthDate == null) {
      setState(() => _error = '生年月日を選択してください。');
      return;
    }
    if (!isOldEnough(birthDate, DateTime.now())) {
      setState(
          () => _error = '$MIN_AGE 歳未満の方はご登録いただけません。');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).saveCreatorProfile(
            fullName: fullName,
            birthDate: birthDate,
            prefectureId: _prefectureId,
            bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
            preferredGenreIds: _genreIds.toList()..sort(),
          );
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
    final AsyncValue<List<MasterItem>> prefectures =
        ref.watch(prefecturesProvider);
    final AsyncValue<List<MasterItem>> genres = ref.watch(genresProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール登録（投稿者）')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _fullName,
                    autofillHints: const <String>[AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: '氏名',
                      helperText: '本人確認にのみ使用し、PR依頼者には表示されません',
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _submitting ? null : _pickBirthDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '生年月日',
                        helperText:
                            '$MIN_AGE 歳以上の方のみ登録できます',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        _birthDate == null
                            ? '選択してください'
                            : DateFormat('yyyy年M月d日').format(_birthDate!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _prefectureId,
                    decoration: const InputDecoration(labelText: '活動エリア（都道府県）'),
                    items: <DropdownMenuItem<int>>[
                      for (final MasterItem p
                          in prefectures.valueOrNull ?? <MasterItem>[])
                        DropdownMenuItem<int>(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (int? value) => setState(() => _prefectureId = value),
                  ),
                  const SizedBox(height: 16),
                  Text('得意なジャンル',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final MasterItem g
                          in genres.valueOrNull ?? <MasterItem>[])
                        FilterChip(
                          label: Text(g.name),
                          selected: _genreIds.contains(g.id),
                          onSelected: _submitting
                              ? null
                              : (bool selected) => setState(() {
                                    if (selected) {
                                      _genreIds.add(g.id);
                                    } else {
                                      _genreIds.remove(g.id);
                                    }
                                  }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _bio,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '自己紹介（任意）',
                      alignLabelWithHint: true,
                    ),
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
                    label: '登録してはじめる',
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
