/// 利用状況イベントの送信をまとめるファイル。
///
/// iOS 版の需要計測やインストール導線の効果測定のために
/// Google Analytics（Firebase Analytics）へイベントを送る。
/// 計測はあくまで補助機能であり、失敗してもアプリの動作を止めては
/// ならないため、すべての送信を握りつぶし式の try-catch で包む。
/// インサイト値・個人情報をパラメータに含めない（AGENTS.md R-7）。
library;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Android アプリのインストール CTA が押されたことを表すイベント名。
const String EVENT_INSTALL_CTA_ANDROID = 'install_cta_android';

/// iOS「Coming Soon」ボタンが押されたことを表すイベント名。
///
/// このイベント数が iOS 版を開発するかどうかの判断材料になる。
const String EVENT_IOS_INTEREST = 'ios_interest';

/// Web お試し版で無効化された機能がタップされたことを表すイベント名。
///
/// どの機能への欲求が強いかをインストール導線の改善に使う。
const String EVENT_WEB_FEATURE_BLOCKED = 'web_feature_blocked';

/// 利用状況イベントを送信するサービス。
class AnalyticsService {
  /// サービスを生成する。
  ///
  /// [logEventImpl] テスト用の送信実装。省略時は Firebase Analytics を使う。
  AnalyticsService({
    Future<void> Function(String name, Map<String, Object>? parameters)?
        logEventImpl,
  }) : _logEventImpl = logEventImpl ?? _sendToFirebase;

  final Future<void> Function(String name, Map<String, Object>? parameters)
      _logEventImpl;

  static Future<void> _sendToFirebase(
    String name,
    Map<String, Object>? parameters,
  ) {
    return FirebaseAnalytics.instance.logEvent(
      name: name,
      parameters: parameters,
    );
  }

  /// イベントを送信する。
  ///
  /// [name] イベント名（本ファイルの定数を使うこと）。
  /// [parameters] 追加パラメータ。個人を特定できる値を入れない。
  /// GA が無効・未設定でも UX を壊さないため、失敗は握りつぶして
  /// デバッグログのみに残す。
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    try {
      await _logEventImpl(name, parameters);
    } on Object catch (error) {
      // 計測は補助機能。失敗しても操作を継続させる。
      debugPrint('analytics 送信に失敗: $name $error');
    }
  }
}

/// イベント送信サービス。テストでは logEventImpl を注入して override する。
final Provider<AnalyticsService> analyticsServiceProvider =
    Provider<AnalyticsService>((Ref ref) => AnalyticsService());
