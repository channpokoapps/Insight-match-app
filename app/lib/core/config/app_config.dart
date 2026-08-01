/// 環境に依存しない公開設定値を保持するファイル。
///
/// ストア URL や規約 URL など「あとから確定する値」を集約し、確定時に
/// このファイル（と リポジトリ直下の `config/app_config.json`）だけを
/// 差し替えれば済む構成にする。資格情報は置かない（それらは env/ 配下）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 環境に依存しない公開設定値。
class AppConfig {
  /// 設定値を生成する。
  ///
  /// [serviceName] サービス名。
  /// [supportEmail] 問い合わせ先メールアドレス。
  /// [termsUrl] 利用規約の URL（空文字は未公開）。
  /// [privacyUrl] プライバシーポリシーの URL(空文字は未公開)。
  /// [termsVersion] 現行の規約バージョン。改定時に更新すると再同意が必要になる。
  /// [androidStoreUrl] Android アプリのストア URL（空文字は未公開）。
  /// [iosStoreUrl] iOS アプリのストア URL（空文字は未公開）。
  /// [isIosAvailable] iOS 版を提供中かどうか。
  const AppConfig({
    required this.serviceName,
    required this.supportEmail,
    required this.termsUrl,
    required this.privacyUrl,
    required this.termsVersion,
    required this.androidStoreUrl,
    required this.iosStoreUrl,
    required this.isIosAvailable,
  });

  /// サービス名。
  final String serviceName;

  /// 問い合わせ先メールアドレス。
  final String supportEmail;

  /// 利用規約の URL。空文字の間は規約画面に本文プレースホルダを表示する。
  final String termsUrl;

  /// プライバシーポリシーの URL。
  final String privacyUrl;

  /// 現行の規約バージョン。`terms_agreements.terms_version` と比較する。
  final String termsVersion;

  /// Android アプリのストア URL。空文字の間はインストール導線が「準備中」表示になる。
  final String androidStoreUrl;

  /// iOS アプリのストア URL。[isIosAvailable] が true になったら設定する。
  final String iosStoreUrl;

  /// iOS 版を提供中かどうか。false の間は導線が「Coming Soon」表示になり、
  /// タップ数を `ios_interest` イベントとして計測する。
  final bool isIosAvailable;

  /// 既定の設定値。`config/app_config.json` と同じ内容を保持する。
  static const AppConfig defaultConfig = AppConfig(
    serviceName: 'Insight Match',
    supportEmail: 'channpoko.apps@gmail.com',
    termsUrl: '',
    privacyUrl: '',
    termsVersion: '2026-08-01',
    androidStoreUrl: '',
    iosStoreUrl: '',
    isIosAvailable: false,
  );
}

/// アプリ全体で共有する設定値。テストではこの Provider を override する。
final Provider<AppConfig> appConfigProvider =
    Provider<AppConfig>((Ref ref) => AppConfig.defaultConfig);
