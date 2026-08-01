/// 初回登録フローの進行段階。
///
/// router はこの値を見て強制的に該当画面へリダイレクトする。
/// **段階の判定はあくまで UI 誘導のため**であり、書き込み可否は
/// サーバー側（RLS）が担保する（AGENTS.md R-8）。
library;

import 'app_role.dart';

enum RegistrationStep {
  /// `profiles` 行が無い。役割（投稿者 / PR依頼者）の選択から。
  roleSelection,

  /// 現行バージョンの規約に未同意。
  termsAgreement,

  /// 役割別プロフィール（creator_profiles / client_profiles）が未入力。
  profileDetails,

  /// 登録完了。通常画面へ進める。
  complete,
}

/// 登録フローの進行段階と、確定していれば役割。
///
/// router は [step] でリダイレクト先を、[role] で役割別ホームを決める。
class RegistrationState {
  const RegistrationState({required this.step, this.role});

  final RegistrationStep step;

  /// `profiles.role`。役割選択前は null。
  final AppRole? role;
}
