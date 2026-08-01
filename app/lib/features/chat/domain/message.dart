/// チャットの 1 通。
///
/// **`senderId` を持たせないこと**（AGENTS.md R-5）。
/// PR依頼者に投稿者の UUID が渡ると案件をまたいだ名寄せが可能になるため、
/// DB 側でも列権限とビュー（`v_chat_messages`）で遮断している。
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.isOwn,
    required this.senderIsClient,
    required this.createdAt,
    this.body,
    this.imagePath,
    this.readAt,
    this.counterpartAliasNo,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('sender_id')) {
      throw StateError('チャットの応答に sender_id が含まれています（AGENTS.md R-5）');
    }
    return ChatMessage(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      isOwn: json['is_own'] as bool? ?? false,
      senderIsClient: json['sender_is_client'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      body: json['body'] as String?,
      imagePath: json['image_path'] as String?,
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
      counterpartAliasNo: (json['counterpart_alias_no'] as num?)?.toInt(),
    );
  }

  final String id;
  final String roomId;

  /// 自分の発言か。相手の identity は分からない。
  final bool isOwn;

  /// 送信者が PR依頼者側か。投稿者側なら false。
  final bool senderIsClient;

  final DateTime createdAt;
  final String? body;
  final String? imagePath;
  final DateTime? readAt;

  /// 案件内連番。PR依頼者から見た相手の表示名に使う。
  final int? counterpartAliasNo;

  bool get isRead => readAt != null;
}

/// チャットルーム。
class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.applicationId,
    required this.isReadonly,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) => ChatRoom(
        id: json['id'] as String,
        applicationId: json['application_id'] as String,
        isReadonly: json['is_readonly'] as bool? ?? false,
      );

  final String id;
  final String applicationId;

  /// 案件終了後などで送信できない状態。
  final bool isReadonly;
}
