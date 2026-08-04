import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/address/postal_code_repository.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/masters/master_repository.dart';
import '../../../shared/widgets/genre_multi_select.dart';
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
  final TextEditingController _genreOther = TextEditingController();
  final TextEditingController _postalCode = TextEditingController();
  final Set<int> _genreIds = <int>{};
  int? _prefectureId;
  int? _cityId;
  bool _submitting = false;
  bool _lookingUp = false;
  String? _postalNotice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _postalCode.addListener(_onPostalCodeChanged);
  }

  @override
  void dispose() {
    _postalCode.removeListener(_onPostalCodeChanged);
    _storeName.dispose();
    _addressLine.dispose();
    _contactEmail.dispose();
    _description.dispose();
    _genreOther.dispose();
    _postalCode.dispose();
    super.dispose();
  }

  /// 7 桁そろった時点で住所を引く。手入力を妨げないよう、失敗しても
  /// 入力済みの値は消さず、案内だけを出す。
  void _onPostalCodeChanged() {
    if (normalizePostalCode(_postalCode.text).length == 7 && !_lookingUp) {
      unawaited(_fillFromPostalCode());
    }
  }

  Future<void> _fillFromPostalCode() async {
    setState(() {
      _lookingUp = true;
      _postalNotice = null;
    });
    try {
      final PostalAddress? address = await ref
          .read(postalCodeRepositoryProvider)
          .lookup(_postalCode.text);
      if (address == null) {
        if (mounted) {
          setState(() => _postalNotice =
              'この郵便番号の住所が見つかりませんでした。住所を直接入力してください。');
        }
        return;
      }
      final ResolvedArea area =
          await ref.read(masterRepositoryProvider).resolveArea(
                prefectureName: address.prefectureName,
                cityName: address.cityName,
              );
      if (!mounted) {
        return;
      }
      setState(() {
        _prefectureId = area.prefectureId;
        _cityId = area.cityId;
        if (address.townName.isNotEmpty) {
          _addressLine.text = address.townName;
        }
        _postalNotice = area.cityId == null
            ? '${address.prefectureName}${address.cityName}'
                ' 市区町村は一覧から選んでください。'
            : null;
      });
    } on AppFailure catch (failure) {
      if (mounted) {
        setState(() => _postalNotice = '${failure.message}'
            ' 住所は直接入力できます。');
      }
    } finally {
      if (mounted) {
        setState(() => _lookingUp = false);
      }
    }
  }

  /// 「その他」を選んでいるときだけ自由記述を送る。
  String? _genreOtherText() {
    final List<MasterItem> genres =
        ref.read(genresProvider).valueOrNull ?? <MasterItem>[];
    if (!GenreMultiSelect.hasOther(genres, _genreIds)) {
      return null;
    }
    final String text = _genreOther.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    final String storeName = _storeName.text.trim();
    if (storeName.isEmpty) {
      setState(() => _error = '店舗・企業名を入力してください。');
      return;
    }
    if (_genreIds.isEmpty) {
      setState(() => _error = 'ジャンルを 1 つ以上選んでください。');
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
            genreIds: _genreIds.toList()..sort(),
            genreOtherText: _genreOtherText(),
            postalCode: normalizePostalCode(_postalCode.text).isEmpty
                ? null
                : normalizePostalCode(_postalCode.text),
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
                  TextField(
                    controller: _postalCode,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(7),
                    ],
                    decoration: InputDecoration(
                      labelText: '郵便番号（任意）',
                      helperText: '7 桁を入力すると住所を自動で入力します',
                      helperMaxLines: 2,
                      suffixIcon: _lookingUp
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (_postalNotice != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      _postalNotice!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  GenreMultiSelect(
                    label: 'ジャンル（複数選択できます）',
                    genres: genres,
                    selectedIds: _genreIds,
                    otherController: _genreOther,
                    enabled: !_submitting,
                    onToggle: (int id, bool selected) => setState(() {
                      if (selected) {
                        _genreIds.add(id);
                      } else {
                        _genreIds.remove(id);
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    // 郵便番号から自動入力したときに表示へ反映させるため、
                    // 選択値をキーにして作り直す。
                    key: ValueKey<String>('pref-$_prefectureId'),
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
                    // 郵便番号からの自動入力も同じ経路で表示に反映する。
                    key: ValueKey<String>('city-$_prefectureId-$_cityId'),
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
