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

