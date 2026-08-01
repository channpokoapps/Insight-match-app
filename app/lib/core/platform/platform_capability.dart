/// 実行プラットフォームごとに利用できる機能を判定するファイル。
///
/// 提供方針: Web 版は「インストール前のお試し版（閲覧専用）」。
/// 案件の閲覧・検索だけを開放し、応募・チャット・SNS 連携などの
/// アクションはすべて Android アプリへ誘導する。
/// 画面側で個別に `kIsWeb` を参照すると判定が散らばるため、
/// 機能単位の問い合わせをこのファイルに集約する（AGENTS.md §3）。
/// なお、この判定は UI の出し分けにすぎず、権限の担保はサーバー側
/// （RLS / RPC）が行う（AGENTS.md R-8）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// アプリが提供する機能の種類。
enum AppFeature {
  /// 案件の閲覧・検索。Web でも利用できる唯一の主要機能。
  campaignBrowsing,

  /// 案件への応募・応募取消。
  campaignApplication,

  /// お気に入り登録。
  favorite,

  /// 1:1 チャット。
  chat,

  /// Instagram など SNS アカウントの連携。
  snsLink,

  /// 案件の作成・編集・公開（PR依頼者）。
  campaignManagement,

  /// 画像のアップロード（案件画像・チャット画像）。
  imageUpload,

  /// PR 投稿 URL の提出。
  postSubmission,

  /// 成果レポートの閲覧。
  reportViewing,

  /// プッシュ通知の受信設定。
  pushNotification,

  /// アカウントの削除（退会）。
  accountDeletion,
}

/// Web 版で無効化する機能。
///
/// 閲覧専用のお試し提供のため、閲覧系（campaignBrowsing / reportViewing）
/// 以外のすべてを無効化する。将来 Web 版の提供範囲を広げる場合はここから
/// 削るだけでよい。
const Set<AppFeature> WEB_DISABLED_FEATURES = <AppFeature>{
  AppFeature.campaignApplication,
  AppFeature.favorite,
  AppFeature.chat,
  AppFeature.snsLink,
  AppFeature.campaignManagement,
  AppFeature.imageUpload,
  AppFeature.postSubmission,
  AppFeature.pushNotification,
  AppFeature.accountDeletion,
};

/// 実行プラットフォームに応じて機能の可否を判定する。
class PlatformCapability {
  /// 判定器を生成する。
  ///
  /// [isWeb] Web 上で動作しているかどうか。省略時は実行環境から判定する。
  /// テストでは明示的に指定して両プラットフォームの挙動を検証する。
  const PlatformCapability({bool? isWeb}) : _isWeb = isWeb ?? kIsWeb;

  final bool _isWeb;

  /// Web 上で動作しているかどうか。
  bool get isWeb => _isWeb;

  /// 指定した機能が利用できるかどうかを返す。
  bool isAvailable(AppFeature feature) {
    if (!_isWeb) {
      return true;
    }
    return !WEB_DISABLED_FEATURES.contains(feature);
  }

  /// 利用できない理由の説明文を返す。
  ///
  /// 戻り値は利用できる場合は null、できない場合は日本語の説明文。
  String? unavailableReason(AppFeature feature) {
    if (isAvailable(feature)) {
      return null;
    }
    return 'この操作はブラウザ版では利用できません。Android アプリをご利用ください。';
  }

  /// Web お試し版の提供範囲の説明文。
  String webTrialNotice() {
    return 'ブラウザ版はお試し提供のため、案件の閲覧のみ利用できます。'
        '応募や SNS 連携には Android アプリをご利用ください。';
  }
}

/// 機能可否の判定器。テストでは isWeb を差し替えて override する。
final Provider<PlatformCapability> platformCapabilityProvider =
    Provider<PlatformCapability>((Ref ref) => const PlatformCapability());
