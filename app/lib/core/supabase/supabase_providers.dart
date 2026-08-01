import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase クライアント。
///
/// 使ってよいのは anon キーのみ。`private` スキーマには到達できない。
final Provider<SupabaseClient> supabaseClientProvider =
    Provider<SupabaseClient>((Ref ref) => Supabase.instance.client);

/// 認証状態の変化。
final StreamProvider<AuthState> authStateProvider =
    StreamProvider<AuthState>((Ref ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// ログイン中のユーザー。未ログインなら null。
final Provider<User?> currentUserProvider = Provider<User?>((Ref ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
});
