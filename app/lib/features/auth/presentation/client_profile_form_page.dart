import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/masters/master_repository.dart';
import '../../../shared/widgets/submit_button.dart';
import '../data/profile_repository.dart';
import '../domain/auth_validators.dart';

/// PR依頼者（店舗・企業）のプロフィール登録画面。
///
/// 店舗情報は案件詳細で投稿者にも表示される（連絡先を除く）。
class ClientProfileFormPage extends ConsumerStatefulWidget {
  const ClientProfileFormPage({super.key});

  @override
  ConsumerState<ClientProfileFormPage> createState() =>
      _ClientProfileFormPageState();
}

class _ClientProfileFormPageState extends ConsumerState<ClientProfileFormPage> {
  final TextEditingController _storeName = TextEditingController();
  final TextEditingController _addressLine = TextEditingController();
  final TextEditingController _contactEmail = TextEditingController();
  final TextEditingController _description = TextEditingController();
  int? _genreId;
  int? _prefectureId;
  int? _cityId;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _storeName.dispose();
    _addressLine.dispose();
    _contactEmail.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String storeName = _storeName.text.trim();
    if (storeName.isEmpty) {
      setState(() => _error = '店舗・企業名を入力してください。');
      return;
    }
    final String contactEmail = _contactEmail.text.trim();
    if (contactEmail.isNotEmpty && !isValidEmail(contactEmail)) {
      setState(() => _error = '連絡先メールアドレスの形式が正しくありません。');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).saveClientProfile(
            storeName: storeName,
            genreId: _genreId,
            prefectureId: _prefectureId,
            cityId: _cityId,
            addressLine: _addressLine.text.trim().isEmpty
                ? null
                : _addressLine.text.trim(),
            contactEmail: contactEmail.isEmpty ? null : contactEmail,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
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
    final AsyncValue<List<MasterItem>>? cities = _prefectureId == null
        ? null
        : ref.watch(_citiesProvider(_prefectureId!));
    return Scaffold(
      appBar: AppBar(title: const Text('店舗情報の登録（PR依頼者）')),
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
                    controller: _storeName,
                    decoration: const InputDecoration(labelText: '店舗・企業名'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _prefectureId,
                    decoration: const InputDecoration(labelText: '都道府県'),
                    items: <DropdownMenuItem<int>>[
                      for (final MasterItem p
                          in prefectures.valueOrNull ?? <MasterItem>[])
                        DropdownMenuItem<int>(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (int? value) => setState(() {
                              _prefectureId = value;
                              _cityId = null;
                            }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    // 都道府県を変えたら市区町村の選択をリセットして作り直す。
                    key: ValueKey<int?>(_prefectureId),
                    initialValue: _cityId,
                    decoration: const InputDecoration(
                      labelText: '市区町村（任意）',
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (final MasterItem c
                          in cities?.valueOrNull ?? <MasterItem>[])
                        DropdownMenuItem<int>(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: _submitting || _prefectureId == null
                        ? null
                        : (int? value) => setState(() => _cityId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressLine,
                    decoration: const InputDecoration(
                      labelText: '住所（任意）',
                      helperText: '案件詳細で投稿者に表示されます',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contactEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: '連絡先メールアドレス（任意）',
                      helperText: '運営からの連絡にのみ使用します',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '店舗紹介（任意）',
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

/// 都道府県別の市区町村一覧。
final FutureProviderFamily<List<MasterItem>, int> _citiesProvider =
    FutureProvider.family<List<MasterItem>, int>(
  (Ref ref, int prefectureId) =>
      ref.watch(masterRepositoryProvider).fetchCities(prefectureId),
);
