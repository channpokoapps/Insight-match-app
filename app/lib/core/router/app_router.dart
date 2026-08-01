import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/sign_in_page.dart';
import '../../features/campaign/presentation/campaign_detail_page.dart';
import '../../features/campaign/presentation/campaign_list_page.dart';
import '../supabase/supabase_providers.dart';

/// 画面遷移の定義。
///
/// 役割（投稿者 / PR依頼者）ごとに到達できる画面が異なるが、
/// **ルーティングは権限の担保ではない**。データの可視性は RLS と RPC が決める。
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    initialLocation: AppRoutes.campaignList,
    redirect: (BuildContext context, GoRouterState state) {
      final bool signedIn = ref.read(currentUserProvider) != null;
      final bool goingToSignIn = state.matchedLocation == AppRoutes.signIn;

      if (!signedIn && !goingToSignIn) {
        return AppRoutes.signIn;
      }
      if (signedIn && goingToSignIn) {
        return AppRoutes.campaignList;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.signIn,
        builder: (BuildContext context, GoRouterState state) => const SignInPage(),
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
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => const Scaffold(
      body: Center(child: Text('ページが見つかりませんでした')),
    ),
  );
});

class AppRoutes {
  const AppRoutes._();

  static const String signIn = '/sign-in';
  static const String campaignList = '/campaigns';

  static String campaignDetail(String id) => '/campaigns/$id';
}
