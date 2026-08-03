import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/profile_repository.dart';
import '../../features/auth/domain/app_role.dart';
import '../../features/auth/domain/registration_step.dart';
import '../../features/auth/presentation/client_profile_form_page.dart';
import '../../features/auth/presentation/creator_profile_form_page.dart';
import '../../features/auth/presentation/password_reset_page.dart';
import '../../features/auth/presentation/role_select_page.dart';
import '../../features/auth/presentation/sign_in_page.dart';
import '../../features/auth/presentation/sign_up_page.dart';
import '../../features/auth/presentation/terms_agreement_page.dart';
import '../../features/auth/presentation/update_password_page.dart';
import '../../features/campaign/presentation/campaign_detail_page.dart';
import '../../features/campaign/presentation/campaign_list_page.dart';
import '../../features/campaign/presentation/client_home_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/sns_link/presentation/sns_link_page.dart';
import '../../shared/widgets/splash_page.dart';
import '../supabase/supabase_providers.dart';

/// 画面遷移の定義。
///
/// 認証・登録段階によるリダイレクトをここに集約する（AGENTS.md §3）。
/// 未ログイン → ログイン系画面、登録未完了 → 該当する登録画面、
/// 完了 → 役割別ホーム、の段階ゲートで誘導する。
/// ただし**ルーティングは権限の担保ではない**。データの可視性は RLS と RPC が決める。
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((Ref ref) {
  // 認証・登録状態が変わるたびに redirect を再評価させる。
  // GoRouter 自体を作り直すと画面スタックが失われるため、Provider の
  // 再生成ではなく refreshListenable で通知する。
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);

  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) =>
        _redirect(ref, state),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (BuildContext context, GoRouterState state) =>
            const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (BuildContext context, GoRouterState state) =>
            const SignInPage(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (BuildContext context, GoRouterState state) =>
            const SignUpPage(),
      ),
      GoRoute(
        path: AppRoutes.passwordReset,
        builder: (BuildContext context, GoRouterState state) =>
            const PasswordResetPage(),
      ),
      GoRoute(
        path: AppRoutes.updatePassword,
        builder: (BuildContext context, GoRouterState state) =>
            const UpdatePasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.registerRole,
        builder: (BuildContext context, GoRouterState state) =>
            const RoleSelectPage(),
      ),
      GoRoute(
        path: AppRoutes.registerTerms,
        builder: (BuildContext context, GoRouterState state) =>
            const TermsAgreementPage(),
      ),
      GoRoute(
        path: AppRoutes.registerDetails,
        builder: (BuildContext context, GoRouterState state) {
          final AppRole? role =
              ref.read(registrationStepProvider).valueOrNull?.role;
          return role == AppRole.client
              ? const ClientProfileFormPage()
              : const CreatorProfileFormPage();
        },
      ),
      GoRoute(
        path: AppRoutes.campaignList,
        builder: (BuildContext context, GoRouterState state) =>
            const CampaignListPage(),
        routes: <RouteBase>[
          GoRoute(
            path: ':campaignId',
            builder: (BuildContext context, GoRouterState state) =>
                CampaignDetailPage(
              campaignId: state.pathParameters['campaignId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.clientHome,
        builder: (BuildContext context, GoRouterState state) =>
            const ClientHomePage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.snsLink,
        builder: (BuildContext context, GoRouterState state) =>
            const SnsLinkPage(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => const Scaffold(
      body: Center(child: Text('ページが見つかりませんでした')),
    ),
  );

  ref.listen<AsyncValue<AuthState>>(authStateProvider,
      (AsyncValue<AuthState>? previous, AsyncValue<AuthState> next) {
    // パスワード再設定メールのリンクから復旧セッションで戻ってきた場合は、
    // 通常のゲートより優先して新パスワード設定画面へ誘導する。
    if (next.valueOrNull?.event == AuthChangeEvent.passwordRecovery) {
      router.go(AppRoutes.updatePassword);
    }
    refresh.value++;
  });
  ref.listen<AsyncValue<RegistrationState?>>(
    registrationStepProvider,
    (AsyncValue<RegistrationState?>? previous,
            AsyncValue<RegistrationState?> next) =>
        refresh.value++,
  );

  return router;
});

/// 認証・登録段階に応じたリダイレクト先を返す。移動不要なら null。
String? _redirect(Ref ref, GoRouterState state) {
  final String location = state.matchedLocation;
  // 認証状態は Repository/Provider 経由でのみ参照する(SupabaseClient.auth を直接触らない)。
  final bool signedIn = ref.read(currentUserProvider) != null;
  final bool atAuthPage = location == AppRoutes.signIn ||
      location == AppRoutes.signUp ||
      location == AppRoutes.passwordReset;

  if (!signedIn) {
    return atAuthPage ? null : AppRoutes.signIn;
  }

  // 復旧セッション中の新パスワード設定は登録段階に関係なく許可する。
  if (location == AppRoutes.updatePassword) {
    return null;
  }

  final AsyncValue<RegistrationState?> stateAsync =
      ref.read(registrationStepProvider);
  final RegistrationState? registration = stateAsync.valueOrNull;
  if (registration == null) {
    // 判定中（または取得失敗直後の再試行中）はスプラッシュに留める。
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  switch (registration.step) {
    case RegistrationStep.roleSelection:
      return location == AppRoutes.registerRole ? null : AppRoutes.registerRole;
    case RegistrationStep.termsAgreement:
      return location == AppRoutes.registerTerms
          ? null
          : AppRoutes.registerTerms;
    case RegistrationStep.profileDetails:
      return location == AppRoutes.registerDetails
          ? null
          : AppRoutes.registerDetails;
    case RegistrationStep.complete:
      final String home = registration.role == AppRole.client
          ? AppRoutes.clientHome
          : AppRoutes.campaignList;
      final bool atTransientPage = atAuthPage ||
          location == AppRoutes.splash ||
          location.startsWith('/register');
      if (atTransientPage) {
        return home;
      }
      // 役割ごとのホームを取り違えないよう相互に弾く。
      if (registration.role == AppRole.client &&
          location.startsWith(AppRoutes.campaignList)) {
        return AppRoutes.clientHome;
      }
      if (registration.role != AppRole.client &&
          location == AppRoutes.clientHome) {
        return AppRoutes.campaignList;
      }
      return null;
  }
}

class AppRoutes {
  const AppRoutes._();

  static const String splash = '/splash';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String passwordReset = '/password-reset';
  static const String updatePassword = '/update-password';
  static const String registerRole = '/register/role';
  static const String registerTerms = '/register/terms';
  static const String registerDetails = '/register/details';
  static const String campaignList = '/campaigns';
  static const String clientHome = '/client';
  static const String settings = '/settings';
  static const String snsLink = '/sns-link';

  static String campaignDetail(String id) => '/campaigns/$id';
}
