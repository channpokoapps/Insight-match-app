/// アカウントの役割。DB の `profiles.role` と対応する。
enum AppRole {
  creator('creator', '投稿者'),
  client('client', 'PR依頼者'),
  admin('admin', '運営');

  const AppRole(this.key, this.label);

  final String key;
  final String label;

  static AppRole? fromKey(String? key) {
    for (final AppRole role in AppRole.values) {
      if (role.key == key) {
        return role;
      }
    }
    return null;
  }
}

/// アカウントの状態。DB の `profiles.status` と対応する。
enum AccountStatus {
  pending('pending', '登録手続き中'),
  active('active', '利用中'),
  suspended('suspended', '停止中'),
  withdrawn('withdrawn', '退会済み');

  const AccountStatus(this.key, this.label);

  final String key;
  final String label;

  static AccountStatus fromKey(String? key) {
    for (final AccountStatus status in AccountStatus.values) {
      if (status.key == key) {
        return status;
      }
    }
    return AccountStatus.pending;
  }
}

/// ログイン中のユーザーの役割と状態。
///
/// 画面の出し分けにのみ使う。**アクセス可否の判定はサーバ側（RLS / RPC）が行う**。
class UserProfile {
  const UserProfile({
    required this.id,
    required this.role,
    required this.status,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        role: AppRole.fromKey(json['role'] as String?) ?? AppRole.creator,
        status: AccountStatus.fromKey(json['status'] as String?),
      );

  final String id;
  final AppRole role;
  final AccountStatus status;

  bool get canUseApp => status == AccountStatus.active;
}
