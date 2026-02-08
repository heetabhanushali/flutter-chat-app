import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  // ============================================================
  // CHAT LIST SUBSCRIPTIONS
  // ============================================================

  RealtimeChannel subscribeToConversationList({
    required Function() onConversationChange,
    required Function(String conversationId) onConversationDeleted,
    required Function(Map<String, dynamic> messageData) onNewMessage,
    required Function() onReadStatusChange,
  }) {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final channel = _supabase
        .channel('chat_updates_$currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) {
            onConversationChange();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_deleted_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUserId,
          ),
          callback: (payload) {
            final deletedConversationId = payload.newRecord['conversation_id'];
            if (deletedConversationId != null) {
              onConversationDeleted(deletedConversationId);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            onNewMessage(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_read_status',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUserId,
          ),
          callback: (payload) {
            onReadStatusChange();
          },
        )
        .subscribe();

    return channel;
  }

  Future<Map<String, dynamic>?> processNewMessageForConversationList(
    Map<String, dynamic> messageData,
  ) async {
    if (currentUserId == null) return null;

    final conversationId = messageData['conversation_id'];
    if (conversationId == null) return null;

    try {
      // Check if this conversation involves the current user
      final conversationCheck = await _supabase
          .from('conversations')
          .select('id, participant1_id, participant2_id')
          .eq('id', conversationId)
          .maybeSingle();

      if (conversationCheck == null) return null;

      final p1 = conversationCheck['participant1_id'];
      final p2 = conversationCheck['participant2_id'];
      if (p1 != currentUserId && p2 != currentUserId) return null;

      // Check if conversation was previously deleted by user
      final deletionResponse = await _supabase
          .from('user_deleted_conversations')
          .select('deleted_at')
          .eq('user_id', currentUserId!)
          .eq('conversation_id', conversationId)
          .maybeSingle();

      if (deletionResponse != null) {
        final deletedAt = deletionResponse['deleted_at'].toString();
        final createdAt = messageData['created_at'].toString();
        
        DateTime deletedAtUtc;
        if (deletedAt.endsWith('Z') || deletedAt.contains('+')) {
          deletedAtUtc = DateTime.parse(deletedAt).toUtc();
        } else {
          deletedAtUtc = DateTime.parse(deletedAt + 'Z').toUtc();
        }

        DateTime messageTimeUtc;
        if (createdAt.endsWith('Z') || createdAt.contains('+')) {
          messageTimeUtc = DateTime.parse(createdAt).toUtc();
        } else {
          messageTimeUtc = DateTime.parse(createdAt + 'Z').toUtc();
        }

        if (!messageTimeUtc.isAfter(deletedAtUtc)) return null;
      }

      // Fetch full conversation data
      final newConv = await _supabase
          .from('conversations')
          .select('''
            id,
            participant1_id,
            participant2_id,
            last_message,
            updated_at,
            participant1:participant1_id(id, username, avatar_url),
            participant2:participant2_id(id, username, avatar_url)
          ''')
          .eq('id', conversationId)
          .maybeSingle();

      if (newConv == null) return null;

      final otherUser = (newConv['participant1_id'] == currentUserId)
          ? newConv['participant2']
          : newConv['participant1'];

      if (otherUser == null) return null;

      return {
        'id': newConv['id'],
        'otherUser': otherUser,
        'lastMessage': newConv['last_message'] ?? '',
        'updatedAt': newConv['updated_at'],
        'senderId': messageData['sender_id'],
      };
    } catch (e) {
      print('Error processing new message: $e');
      return null;
    }
  }

  // ============================================================
  // PERSONAL CHAT SUBSCRIPTIONS
  // ============================================================

  /// Sets up realtime subscription for messages in a conversation
  RealtimeChannel subscribeToMessages({
    required String conversationId,
    required Function(Map<String, dynamic> messageData) onNewMessage,
    Function(String error)? onError,
  }) {
    final channel = _supabase
        .channel('messages_${conversationId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            onNewMessage(payload.newRecord);
          },
        )
        .subscribe((status, error) {
          if (error != null && onError != null) {
            onError(error.toString());
          }
        });

    return channel;
  }

  /// Sets up realtime subscription for read status changes
  RealtimeChannel subscribeToReadStatus({
    required String recipientId,
    required Function(String messageId, DateTime readAt) onMessageRead,
    required bool Function(String messageId) messageExistsCheck,
    Function(String error)? onError,
  }) {
    
    final channel = _supabase
        .channel('read_status_${recipientId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_read_status',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: recipientId,
          ),
          callback: (payload) {
            
            final newReadStatus = payload.newRecord;
            final messageId = newReadStatus['message_id'];
            final readAt = newReadStatus['read_at'];

            if (messageId != null && readAt != null) {
              if (messageExistsCheck(messageId)) {
                DateTime readTime;
                if (readAt.toString().endsWith('Z') || readAt.toString().contains('+')) {
                  readTime = DateTime.parse(readAt).toLocal();
                } else {
                  readTime = DateTime.parse(readAt + 'Z').toLocal();
                }
                onMessageRead(messageId, readTime);
              }
            }
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            print('Read status subscription error: $error');
            if (onError != null) {
              onError(error.toString());
            }
          }
        });

    return channel;
  }

  // ============================================================
  // UTILITY
  // ============================================================

  /// Unsubscribes from a channel
  void unsubscribe(RealtimeChannel? channel) {
    channel?.unsubscribe();
  }

}

