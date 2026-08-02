import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env/env.dart';
import 'core/firebase/web_firebase_options.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();

  // 旧 anon キー・新 publishable キーのどちらも渡せる（RLS 前提の公開キー）。
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  // Firebase は GA4 計測（と将来の FCM）のみに使う補助機能。
  // 未設定・初期化失敗でもアプリの起動は継続する。
  await _initializeFirebase();

  runApp(const ProviderScope(child: App()));
}

Future<void> _initializeFirebase() async {
  try {
    if (kIsWeb) {
      if (!hasWebFirebaseConfig()) {
        // 本番ビルドの設定漏れはインストール導線の計測が丸ごと欠けるため警告する。
        debugPrint(
          'Firebase 設定が未注入のため GA4 計測を無効化しました'
          '（env/web_firebase_config.json / docs/manual_setup/gcp_firebase.md 参照）。',
        );
        return;
      }
      await Firebase.initializeApp(options: buildWebFirebaseOptions());
      return;
    }
    // Android は google-services.json（配置時のみ）から初期化される。
    await Firebase.initializeApp();
  } on Object catch (error) {
    debugPrint('Firebase 初期化をスキップ: $error');
  }
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SNS Insight Matcher',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('ja'),
      supportedLocales: const <Locale>[Locale('ja'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
