import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight_match/core/analytics/analytics_service.dart';
import 'package:insight_match/core/config/app_config.dart';
import 'package:insight_match/shared/widgets/install_prompt.dart';

/// テスト用の設定値を作る。
AppConfig _config({String androidStoreUrl = '', bool iosAvailable = false}) {
  return AppConfig(
    serviceName: 'Insight Match',
    supportEmail: 'test@example.com',
    termsUrl: '',
    privacyUrl: '',
    termsVersion: '2026-08-01',
    androidStoreUrl: androidStoreUrl,
    iosStoreUrl: '',
    isIosAvailable: iosAvailable,
  );
}

Widget _wrap({
  required AppConfig config,
  required List<String> loggedEvents,
  required List<Uri> launchedUrls,
}) {
  return ProviderScope(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(config),
      analyticsServiceProvider.overrideWithValue(
        AnalyticsService(
          logEventImpl: (String name, Map<String, Object>? parameters) async {
            loggedEvents.add(name);
          },
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: AppInstallButtons(
          launchUrlImpl: (Uri url) async {
            launchedUrls.add(url);
            return true;
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Android: ストア URL 未設定でもイベントを送り「準備中」を表示する', (
    WidgetTester tester,
  ) async {
    final List<String> logged = <String>[];
    final List<Uri> launched = <Uri>[];
    await tester.pumpWidget(
      _wrap(config: _config(), loggedEvents: logged, launchedUrls: launched),
    );

    await tester.tap(find.text('Android アプリを入手'));
    await tester.pumpAndSettle();

    expect(logged, contains(EVENT_INSTALL_CTA_ANDROID));
    expect(launched, isEmpty);
    expect(find.text('Android アプリは準備中です'), findsOneWidget);
  });

  testWidgets('Android: ストア URL 設定後はイベントを送ってストアを開く', (
    WidgetTester tester,
  ) async {
    const String storeUrl =
        'https://play.google.com/store/apps/details?id=app.insightmatch.android';
    final List<String> logged = <String>[];
    final List<Uri> launched = <Uri>[];
    await tester.pumpWidget(
      _wrap(
        config: _config(androidStoreUrl: storeUrl),
        loggedEvents: logged,
        launchedUrls: launched,
      ),
    );

    await tester.tap(find.text('Android アプリを入手'));
    await tester.pumpAndSettle();

    expect(logged, contains(EVENT_INSTALL_CTA_ANDROID));
    expect(launched, <Uri>[Uri.parse(storeUrl)]);
    expect(find.text('Android アプリは準備中です'), findsNothing);
  });

  testWidgets('iOS: 未提供の間は ios_interest を送って Coming Soon を表示する', (
    WidgetTester tester,
  ) async {
    final List<String> logged = <String>[];
    final List<Uri> launched = <Uri>[];
    await tester.pumpWidget(
      _wrap(config: _config(), loggedEvents: logged, launchedUrls: launched),
    );

    await tester.tap(find.text('iOS 版 (Coming Soon)'));
    await tester.pumpAndSettle();

    expect(logged, contains(EVENT_IOS_INTEREST));
    expect(launched, isEmpty);
    expect(find.text('iOS 版は Coming Soon'), findsOneWidget);
  });
}
