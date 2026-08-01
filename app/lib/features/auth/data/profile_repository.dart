import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/app_role.dart';

/// ログイン中ユーザーのプロフィール取得。
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

  Future<void> signOut() => _client.auth.signOut();
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
