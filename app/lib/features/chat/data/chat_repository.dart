import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/message.dart';

/// チャットの参照・送信。
///
/// 参照は `v_chat_messages` 経由に限る。`messages` を直接 select すると
/// sender_id の列権限が無いため失敗する（0007_chat_sender_masking.sql）。
///
/// TODO(OI-43): リアルタイム受信の方式が未決。`postgres_changes` は行全体を
/// 配信し sender_id が漏れるため、現状は再取得で更新している。
class ChatRepository {
  const ChatRepository(this._client);

  final SupabaseClient _client;

  Future<ChatRoom?> findRoomByApplication(String applicationId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('chat_rooms')
          .select('id, application_id, is_readonly')
          .eq('application_id', applicationId)
          .maybeSingle();
      return row == null ? null : ChatRoom.fromJson(row);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('chat.find_room_failed', failure.code, s);
      throw failure;
    }
  }

  Future<List<ChatMessage>> listMessages(
    String roomId, {
    int limit = 50,
    DateTime? before,
  }) async {
    try {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
          .from('v_chat_messages')
          .select(
            'id, room_id, body, image_path, read_at, created_at, '
            'is_own, sender_is_client, counterpart_alias_no',
          )
          .eq('room_id', roomId);
      if (before != null) {
        query = query.lt('created_at', before.toIso8601String());
      }
      final List<Map<String, dynamic>> rows =
          await query.order('created_at', ascending: false).limit(limit);
      return rows.map(ChatMessage.fromJson).toList();
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('chat.list_messages_failed', failure.code, s);
      throw failure;
    }
  }

  /// 送信。sender_id は自分の ID しか入れられない（RLS で保証）。
  Future<void> send({
    required String roomId,
    String? body,
    String? imagePath,
  }) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AppFailure(FailureKind.unauthorized, 'ログインが必要です。');
    }
    if ((body == null || body.trim().isEmpty) && imagePath == null) {
      throw const AppFailure(FailureKind.conflict, 'メッセージを入力してください。');
    }
    try {
      await _client.from('messages').insert(<String, dynamic>{
        'room_id': roomId,
        'sender_id': userId,
        'body': body?.trim(),
        'image_path': imagePath,
      });
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('chat.send_failed', failure.code, s);
      throw failure;
    }
  }

  Future<void> markRead(String messageId) async {
    try {
      await _client
          .from('messages')
          .update(<String, dynamic>{'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', messageId);
    } on Object catch (e, s) {
      final AppFailure failure = AppFailure.from(e);
      AppLogger.error('chat.mark_read_failed', failure.code, s);
      throw failure;
    }
  }
}

final Provider<ChatRepository> chatRepositoryProvider = Provider<ChatRepository>(
  (Ref ref) => ChatRepository(ref.watch(supabaseClientProvider)),
);

final FutureProviderFamily<List<ChatMessage>, String> chatMessagesProvider =
    FutureProvider.family<List<ChatMessage>, String>(
  (Ref ref, String roomId) => ref.watch(chatRepositoryProvider).listMessages(roomId),
);
