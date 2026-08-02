import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../features/auth/data/profile_repository.dart';
import '../../features/auth/domain/app_role.dart';

/// 役割別のボトムナビゲーション。
///
/// Instagram / LINE と同じ「下タブで主要画面を行き来する」操作感に揃える。
/// タブ間は push ではなく go で置き換え、戻るボタンの山を作らない。
class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({required this.current, super.key});

  /// 現在表示中の画面のルート([AppRoutes] の定数)。
  final String current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 設定タブは両役割で共有のため、現在地だけでは役割を特定できない。
    // 登録ゲート通過後は registrationStepProvider が解決済みなのでそれを使う。
    final AppRole? role = current == AppRoutes.clientHome
        ? AppRole.client
        : (current == AppRoutes.campaignList || current == AppRoutes.snsLink)
            ? AppRole.creator
            : ref.watch(registrationStepProvider).valueOrNull?.role;

    final List<_NavItem> items = role == AppRole.client
        ? const <_NavItem>[
            _NavItem(
              route: AppRoutes.clientHome,
              icon: Icons.campaign_outlined,
              selectedIcon: Icons.campaign,
              label: '案件',
            ),
            _NavItem(
              route: AppRoutes.settings,
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: 'マイページ',
            ),
          ]
        : const <_NavItem>[
            _NavItem(
              route: AppRoutes.campaignList,
              icon: Icons.search,
              selectedIcon: Icons.search,
              label: 'さがす',
            ),
            _NavItem(
              route: AppRoutes.snsLink,
              icon: Icons.add_link,
              selectedIcon: Icons.link,
              label: 'SNS連携',
            ),
            _NavItem(
              route: AppRoutes.settings,
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: 'マイページ',
            ),
          ];

    int selected = items.indexWhere((_NavItem item) => item.route == current);
    if (selected < 0) {
      selected = 0;
    }

    return NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (int index) {
        final String route = items[index].route;
        if (route != current) {
          context.go(route);
        }
      },
      destinations: items
          .map(
            (_NavItem item) => NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
          )
          .toList(),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
