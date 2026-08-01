/// 応募の状態。DB の `applications.status` と対応する。
enum ApplicationStatus {
  applied('applied', '応募中'),
  screening('screening', '選考中'),
  matched('matched', 'マッチング成立'),
  rejected('rejected', '見送り'),
  withdrawn('withdrawn', '応募取消'),
  cancelRequested('cancel_requested', 'キャンセル申請中'),
  cancelled('cancelled', 'キャンセル'),
  posted('posted', '投稿済み'),
  noPost('no_post', '未投稿'),
  completed('completed', '完了');

  const ApplicationStatus(this.key, this.label);

  final String key;
  final String label;

  static ApplicationStatus fromKey(String? key) {
    for (final ApplicationStatus status in ApplicationStatus.values) {
      if (status.key == key) {
        return status;
      }
    }
    return ApplicationStatus.applied;
  }

  bool get isActive => const <ApplicationStatus>{
        ApplicationStatus.applied,
        ApplicationStatus.screening,
        ApplicationStatus.matched,
        ApplicationStatus.cancelRequested,
        ApplicationStatus.posted,
      }.contains(this);
}

/// 案件内連番から表示名を作る。
///
/// 連番は案件ごとに独立しているため、別案件の同じラベルが同一人物とは限らない
/// （ADR-0005）。この性質が名寄せを防いでいる。
class CreatorAlias {
  const CreatorAlias._();

  /// 1 → 投稿者A、26 → 投稿者Z、27 → 投稿者AA。
  static String label(int aliasNo) {
    if (aliasNo < 1) {
      return '投稿者';
    }
    final List<int> codeUnits = <int>[];
    int n = aliasNo;
    while (n > 0) {
      final int remainder = (n - 1) % 26;
      codeUnits.add(65 + remainder);
      n = (n - 1) ~/ 26;
    }
    return '投稿者${String.fromCharCodes(codeUnits.reversed)}';
  }
}

/// PR依頼者から見た応募。
///
/// **`creatorId` に相当するフィールドを絶対に追加しないこと**（AGENTS.md R-5）。
/// 型として存在させないことが最後の防御線になる。
class ApplicationForClient {
  const ApplicationForClient({
    required this.id,
    required this.campaignId,
    required this.aliasNo,
    required this.status,
    required this.appliedAt,
    required this.hasSubmission,
    required this.isPostVerified,
    this.message,
  });

  factory ApplicationForClient.fromJson(Map<String, dynamic> json) {
    // ビューの定義が変わって識別情報が混入した場合に、気付かず表示してしまわないようにする。
    for (final String forbidden in _forbiddenKeys) {
      if (json.containsKey(forbidden)) {
        throw StateError(
          'PR依頼者向けの応答に識別情報が含まれています: $forbidden（AGENTS.md R-5）',
        );
      }
    }
    return ApplicationForClient(
      id: json['id'] as String,
      campaignId: json['campaign_id'] as String,
      aliasNo: json['alias_no'] as int,
      status: ApplicationStatus.fromKey(json['status'] as String?),
      appliedAt: DateTime.parse(json['created_at'] as String),
      hasSubmission: json['has_submission'] as bool? ?? false,
      isPostVerified: json['is_post_verified'] as bool? ?? false,
      message: json['message'] as String?,
    );
  }

  static const Set<String> _forbiddenKeys = <String>{
    'creator_id',
    'user_id',
    'display_name',
    'sns_username',
    'email',
  };

  final String id;
  final String campaignId;

  /// 案件内連番。案件をまたいだ同一性は持たない。
  final int aliasNo;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final bool hasSubmission;
  final bool isPostVerified;

  /// 応募時のメッセージ。氏名等が書かれる可能性があるため画面側で扱いに注意する。
  final String? message;

  String get displayName => CreatorAlias.label(aliasNo);
}

/// 投稿者から見た自分の応募。
class MyApplication {
  const MyApplication({
    required this.id,
    required this.campaignId,
    required this.campaignTitle,
    required this.status,
    required this.appliedAt,
    this.chatRoomId,
    this.postDeadlineAt,
  });

  factory MyApplication.fromJson(Map<String, dynamic> json) => MyApplication(
        id: json['id'] as String,
        campaignId: json['campaign_id'] as String,
        campaignTitle: json['campaign_title'] as String? ?? '',
        status: ApplicationStatus.fromKey(json['status'] as String?),
        appliedAt: DateTime.parse(json['created_at'] as String),
        chatRoomId: json['chat_room_id'] as String?,
        postDeadlineAt: json['post_end_at'] == null
            ? null
            : DateTime.parse(json['post_end_at'] as String),
      );

  final String id;
  final String campaignId;
  final String campaignTitle;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final String? chatRoomId;
  final DateTime? postDeadlineAt;
}
