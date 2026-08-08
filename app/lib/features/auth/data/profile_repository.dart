import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/app_role.dart';
import '../domain/client_profile.dart';
import '../domain/registration_step.dart';

/// ログイン中ユーザーのプロフィール取得と初回登録フローの書き込み。
///
/// `profiles` は RLS で自分の行しか見えないため、他人の役割は取得できない。
class ProfileRepository {
  const ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<UserProfile?> fetchMine() async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }
    try {
      final Map<String, dynamic>? row = await _client
          .from('profiles')
          .select('id, role, status')
          .eq('id', userId)
          .maybeSingle();
      return row == null ? null : UserProfile.fromJson(row);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('profile.fetch_failed', failure.code, s);
      throw failure;
    }
  }

  /// 役割を選択して `profiles` 行を作成する。
  ///
  /// admin は選択できない（RLS の `profiles_insert_self` も拒否する）。
  Future<void> createProfile(AppRole role) async {
    final String userId = _requireUserId();
    try {
      await _client.from('profiles').insert(<String, dynamic>{
        'id': userId,
        'role': role.key,
      });
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('profile.create_failed', failure.code, s);
      throw failure;
    }
  }

  /// 指定バージョンの規約に同意済みかどうかを返す。
  Future<bool> hasAgreedTo(String termsVersion) async {
    final String userId = _requireUserId();
    try {
      final Map<String, dynamic>? row = await _client
          .from('terms_agreements')
          .select('id')
          .eq('user_id', userId)
          .eq('terms_version', termsVersion)
          .limit(1)
          .maybeSingle();
      return row != null;
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('terms.check_failed', failure.code, s);
      throw failure;
    }
  }

  /// 指定バージョンの規約への同意を記録する。
  Future<void> agreeTo(String termsVersion) async {
    final String userId = _requireUserId();
    try {
      await _client.from('terms_agreements').insert(<String, dynamic>{
        'user_id': userId,
        'terms_version': termsVersion,
      });
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('terms.agree_failed', failure.code, s);
      throw failure;
    }
  }

  /// 投稿者プロフィールを保存し、アカウントを利用可能にする。
  ///
  /// [preferredGenreIds] 希望ジャンル。[prefectureId] 活動エリア。
  /// 年齢確認（18 歳以上）は呼び出し側の画面で行う（OI-08）。
  Future<void> saveCreatorProfile({
    required String fullName,
    required DateTime birthDate,
    int? prefectureId,
    String? bio,
    List<int> preferredGenreIds = const <int>[],
    String? genreOtherText,
  }) async {
    final String userId = _requireUserId();
    try {
      await _client.from('creator_profiles').upsert(<String, dynamic>{
        'user_id': userId,
        'full_name': fullName,
        'birth_date':
            '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
        'prefecture_id': prefectureId,
        'bio': bio,
        'preferred_genre_ids': preferredGenreIds,
        'genre_other_text': genreOtherText,
      });
      await _activateAccount(userId);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('profile.creator_save_failed', failure.code, s);
      throw failure;
    }
  }

  /// 自分の PR依頼者プロフィールを返す。未登録なら null。
  ///
  /// 登録後の編集画面（FR-AUTH-07）と、案件フォームの初期値（FR-CMP-02）が読む。
  Future<ClientProfile?> fetchClientProfile() async {
    final String userId = _requireUserId();
    try {
      final Map<String, dynamic>? row = await _client
          .from('client_profiles')
          .select('store_name, genre_ids, genre_other_text, postal_code, '
              'prefecture_id, city_id, address_line, latitude, longitude, '
              'nearest_station_id, contact_email, description')
          .eq('user_id', userId)
          .maybeSingle();
      return row == null ? null : ClientProfile.fromJson(row);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('profile.client_fetch_failed', failure.code, s);
      throw failure;
    }
  }

  /// PR依頼者（店舗）プロフィールを保存し、アカウントを利用可能にする。
  ///
  /// 初回登録と登録後の編集（FR-AUTH-07）で共用する。upsert のため
  /// 既存行があれば上書きし、アカウント状態は pending のときだけ active にする。
  ///
  /// [genreIds] は飲食ジャンルの複数選択。「その他」を選んだときだけ
  /// [genreOtherText] に自由記述が入る（運営がマスタ昇格の判断に使う）。
  Future<void> saveClientProfile({
    required String storeName,
    List<int> genreIds = const <int>[],
    String? genreOtherText,
    String? postalCode,
    int? prefectureId,
    int? cityId,
    String? addressLine,
    int? nearestStationId,
    String? contactEmail,
    String? description,
  }) async {
    final String userId = _requireUserId();
    try {
      await _client.from('client_profiles').upsert(<String, dynamic>{
        'user_id': userId,
        'store_name': storeName,
        'genre_ids': genreIds,
        'genre_other_text': genreOtherText,
        'postal_code': postalCode,
        'prefecture_id': prefectureId,
        'city_id': cityId,
        'address_line': addressLine,
        'nearest_station_id': nearestStationId,
        'contact_email': contactEmail,
        'description': description,
      });
      await _activateAccount(userId);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('profile.client_save_failed', failure.code, s);
      throw failure;
    }
  }

  /// 初回登録フローの進行段階を判定する。
  ///
  /// [termsVersion] 現行の規約バージョン。
  Future<RegistrationState> fetchRegistrationState(String termsVersion) async {
    final UserProfile? profile = await fetchMine();
    if (profile == null) {
      return const RegistrationState(step: RegistrationStep.roleSelection);
    }
    if (!await hasAgreedTo(termsVersion)) {
      return RegistrationState(
        step: RegistrationStep.termsAgreement,
        role: profile.role,
      );
    }
    // admin は手動作成のアカウントで役割別プロフィールを持たない。
    if (profile.role == AppRole.admin) {
      return const RegistrationState(
        step: RegistrationStep.complete,
        role: AppRole.admin,
      );
    }
    final String table =
        profile.role == AppRole.client ? 'client_profiles' : 'creator_profiles';
    try {
      final Map<String, dynamic>? row = await _client
          .from(table)
          .select('user_id')
          .eq('user_id', profile.id)
          .maybeSingle();
      if (row == null) {
        return RegistrationState(
          step: RegistrationStep.profileDetails,
          role: profile.role,
        );
      }
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('profile.step_check_failed', failure.code, s);
      throw failure;
    }
    return RegistrationState(
      step: RegistrationStep.complete,
      role: profile.role,
    );
  }

  Future<void> _activateAccount(String userId) async {
    await _client
        .from('profiles')
        .update(<String, dynamic>{'status': 'active'})
        .eq('id', userId)
        .eq('status', 'pending');
  }

  String _requireUserId() {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AppFailure(FailureKind.unauthorized, 'ログインが必要です。');
    }
    return userId;
  }
}

final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>(
  (Ref ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);

/// ログイン状態が変わったら再取得する。
final FutureProvider<UserProfile?> myProfileProvider =
    FutureProvider<UserProfile?>((Ref ref) {
  ref.watch(authStateProvider);
  return ref.watch(profileRepositoryProvider).fetchMine();
});

/// 画面の出し分け用。取得前は null。
final Provider<AppRole?> myRoleProvider = Provider<AppRole?>(
  (Ref ref) => ref.watch(myProfileProvider).valueOrNull?.role,
);

/// 自分の店舗プロフィール。未登録なら null。
///
/// 編集して保存したら invalidate する。案件フォームの初期値
/// （`storeDefaultsProvider`）もこれを見ているため、同時に追従する。
final FutureProvider<ClientProfile?> clientProfileProvider =
    FutureProvider<ClientProfile?>((Ref ref) {
  ref.watch(authStateProvider);
  return ref.watch(profileRepositoryProvider).fetchClientProfile();
});

/// 初回登録フローの進行段階。未ログイン時は null。
///
/// 各登録画面が書き込み後に `ref.invalidate` することで router が次の段階へ進める。
final FutureProvider<RegistrationState?> registrationStepProvider =
    FutureProvider<RegistrationState?>((Ref ref) async {
  ref.watch(authStateProvider);
  final bool signedIn =
      ref.watch(supabaseClientProvider).auth.currentUser != null;
  if (!signedIn) {
    return null;
  }
  final String termsVersion = ref.watch(appConfigProvider).termsVersion;
  return ref
      .watch(profileRepositoryProvider)
      .fetchRegistrationState(termsVersion);
});
