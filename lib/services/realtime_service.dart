import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/services/connectivity_service.dart';

class RealtimeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ConnectivityService _connectivity = ConnectivityService();
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
          if (error != null && onError != null && _connectivity.isOnline) {
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
          if (error != null && _connectivity.isOnline) {
            print('Read status subscription error: $error');
            if (onError != null) {
              onError(error.toString());
            }
          }
        });

    return channel;
  }

  // ============================================================
  // TYPING INDICATOR
  // ============================================================

  RealtimeChannel? _typingChannel;
  String? _currentTypingConversationId;

  /// Subscribe to typing events AND enable broadcasting on same channel
  RealtimeChannel subscribeToTyping({
    required String conversationId,
    required Function(String userId) onUserTyping,
  }) {
    // Clean up old channel
    _typingChannel?.unsubscribe();

    _currentTypingConversationId = conversationId;

    _typingChannel = _supabase
        .channel('typing_$conversationId')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final typingUserId = payload['user_id'] as String?;
            if (typingUserId != null && typingUserId != currentUserId) {
              onUserTyping(typingUserId);
            }
          },
        )
        .subscribe();

    return _typingChannel!;
  }

  /// Broadcast typing on the SAME channel that's already subscribed
  Future<void> broadcastTyping({
    required String conversationId,
  }) async {
    if (currentUserId == null) return;
    if (_typingChannel == null) return;
    if (_currentTypingConversationId != conversationId) return;

    try {
      await _typingChannel!.sendBroadcastMessage(
        event: 'typing',
        payload: {
          'user_id': currentUserId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      print('Typing broadcast failed: $e');
    }
  }

  // ============================================================
  // UTILITY
  // ============================================================

  /// Unsubscribes from a channel
  void unsubscribe(RealtimeChannel? channel) {
    channel?.unsubscribe();
  }

}

