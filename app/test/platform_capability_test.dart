import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/platform/platform_capability.dart';

void main() {
  group('PlatformCapability', () {
    const PlatformCapability web = PlatformCapability(isWeb: true);
    const PlatformCapability android = PlatformCapability(isWeb: false);

    test('Android では全機能が利用できる', () {
      for (final AppFeature feature in AppFeature.values) {
        expect(android.isAvailable(feature), isTrue, reason: feature.name);
        expect(android.unavailableReason(feature), isNull);
      }
    });

    test('Web は閲覧系のみ利用できる（閲覧専用お試し版）', () {
      expect(web.isAvailable(AppFeature.campaignBrowsing), isTrue);
      expect(web.isAvailable(AppFeature.reportViewing), isTrue);
    });

    test('Web ではアクション系がすべて無効になる', () {
      const List<AppFeature> actions = <AppFeature>[
        AppFeature.campaignApplication,
        AppFeature.favorite,
        AppFeature.chat,
        AppFeature.snsLink,
        AppFeature.campaignManagement,
        AppFeature.imageUpload,
        AppFeature.postSubmission,
        AppFeature.pushNotification,
        AppFeature.accountDeletion,
      ];
      for (final AppFeature feature in actions) {
        expect(web.isAvailable(feature), isFalse, reason: feature.name);
        expect(
          web.unavailableReason(feature),
          contains('Android アプリ'),
          reason: feature.name,
        );
      }
    });

    test('無効化リストは閲覧系を含まない（更新時の事故防止）', () {
      expect(
        WEB_DISABLED_FEATURES,
        isNot(contains(AppFeature.campaignBrowsing)),
      );
      expect(WEB_DISABLED_FEATURES, isNot(contains(AppFeature.reportViewing)));
    });
  });
}
