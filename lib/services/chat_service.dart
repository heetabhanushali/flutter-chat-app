import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  // ===============================================
  // Deletion
  // ===============================================

  Future<bool> deleteConversationForUser(String conversationId) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Remove any existing deletion record for this conversation
      await _supabase
          .from('user_deleted_conversations')
          .delete()
          .eq('user_id', currentUserId!)
          .eq('conversation_id', conversationId);

      
      final deletionTime = DateTime.now().toUtc().toIso8601String();

      await _supabase
          .from('user_deleted_conversations')
          .insert({
            'user_id': currentUserId,
            'conversation_id': conversationId,
            'deleted_at': deletionTime,
          });

      // print("CONVERSATION IS DELETED / UPDATED");
      return true;
    } catch (e) {
      print('Error deleting conversation: $e');
      rethrow;
    }
  }

  Future<DateTime?> getConversationDeletionTime(String conversationId) async {
    if (currentUserId == null) return null;

    try {
      final response = await _supabase
          .from('user_deleted_conversations')
          .select('deleted_at')
          .eq('user_id', currentUserId!)
          .eq('conversation_id', conversationId)
          .maybeSingle();

      if (response != null) {
        return DateTime.parse(response['deleted_at']).toUtc();
        // print("getConversationDeletiontime: ${deletedAt}");
      }

      return null;
    } catch (e) {
      print('Error getting conversation deletion time: $e');
      return null;
    }
  }

  // ===============================================
  // CONVERSATION MANAGEMENT
  // ===============================================

  /// Fetches all conversations for the current user using RPC
  /// Single database call instead of multiple
  Future<List<Map<String, dynamic>>> loadConversations() async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final response = await _supabase.rpc(
        'get_user_conversations',
        params: {'p_user_id': currentUserId},
      );

      final List<Map<String, dynamic>> result = [];

      for (final conv in response) {
        result.add({
          'id': conv['conversation_id'],
          'otherUser': {
            'id': conv['other_user_id'],
            'username': conv['other_user_username'],
            'avatar_url': conv['other_user_avatar_url'],
          },
          'lastMessage': conv['last_message'] ?? '',
          'updatedAt': conv['updated_at'],
          'isUnread': conv['is_unread'] ?? false,
        });
      }

      return result;
    } catch (e) {
      print('Error loading conversations: $e');
      rethrow;
    }
  }

  Future<String?> getExistingConversation(String recipientId, {bool markAsRead = false}) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final existingConversation = await _supabase
          .from('conversations')
          .select('id')
          .or(
            'and(participant1_id.eq.$currentUserId,participant2_id.eq.$recipientId),'
            'and(participant1_id.eq.$recipientId,participant2_id.eq.$currentUserId)'
          )
          .maybeSingle();

      final conversationId = existingConversation?['id'];

      if (conversationId != null && markAsRead) {
        await markAllMessagesAsRead(conversationId);
      }

      return conversationId;
    } catch (e) {
      print('Error getting existing conversation: $e');
      rethrow;
    }
  }

  Future<String?> getOrCreateConversation(String recipientId) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Check for existing conversation first
      final existingId = await getExistingConversation(recipientId);
      if (existingId != null) {
        return existingId;
      }

      // Create new conversation
      final now = DateTime.now().toUtc().toIso8601String();
      final newConversation = await _supabase.from('conversations').insert({
        'participant1_id': currentUserId,
        'participant2_id': recipientId,
        'created_at': now,
        'updated_at': now,
      }).select('id').single();

      return newConversation['id'];
    } catch (e) {
      print('Error creating conversation: $e');
      rethrow;
    }
  }

  // ===============================================
  // MESSAGE MANAGEMENT
  // ===============================================

  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final deletedAt = await getConversationDeletionTime(conversationId);

      // Fetch all messages for the conversation
      final messages = await _supabase
          .from('messages')
          .select('*, sender:users!messages_sender_id_fkey(username, avatar_url)')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      // Filter messages based on deletion time
      if (deletedAt != null) {
        final filteredMessages = messages.where((msg) {
          final rawTime = msg['created_at'];
          DateTime msgTimeUtc;
          
          if (rawTime.toString().endsWith('Z') || rawTime.toString().contains('+')) {
            msgTimeUtc = DateTime.parse(rawTime);
          } else {
            msgTimeUtc = DateTime.parse(rawTime + 'Z').toUtc();
          }
          
          // print("Message time : ${msgTimeUtc}, Deleted at: ${deletedAt}");

          return msgTimeUtc.isAfter(deletedAt);
        }).toList();

        return List<Map<String, dynamic>>.from(filteredMessages);
      }

      return List<Map<String, dynamic>>.from(messages);
    } catch (e) {
      print('Error loading messages: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // Insert message
      final message = await _supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': currentUserId,
        'content': content,
        'created_at': now,
      }).select().single();

      // Update conversation's last message
      await _supabase.from('conversations').update({
        'last_message': content,
        'updated_at': now,
      }).eq('id', conversationId);

      return message;
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  // ============================================================
  // READ STATUS MANAGEMENT
  // ============================================================

  Future<void> markConversationAsRead(String conversationId) async {
    if (currentUserId == null) return;

    try {
      // Get latest message in conversation
      final latestMessage = await _supabase
          .from('messages')
          .select('id, sender_id')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (latestMessage == null) return;

      // If current user sent the latest message, no need to mark as read
      if (latestMessage['sender_id'] == currentUserId) return;

      // Check if already marked as read
      final existingRead = await _supabase
          .from('message_read_status')
          .select('id')
          .eq('message_id', latestMessage['id'])
          .eq('user_id', currentUserId!)
          .maybeSingle();

      // Only insert if not already marked as read
      if (existingRead == null) {
        await _supabase
            .from('message_read_status')
            .insert({
              'message_id': latestMessage['id'],
              'user_id': currentUserId,
            });
      }
    } catch (e) {
      print('Error marking conversation as read: $e');
    }
  }

  Future<void> markMessageAsRead(String messageId, String senderId) async {
    if (currentUserId == null) return;
    
    // Don't mark own messages as read
    if (senderId == currentUserId) return;

    try {
      // Check if already marked as read
      final existingRead = await _supabase
          .from('message_read_status')
          .select('id')
          .eq('message_id', messageId)
          .eq('user_id', currentUserId!)
          .maybeSingle();

      // Only insert if not already marked as read
      if (existingRead == null) {
        await _supabase
            .from('message_read_status')
            .insert({
              'message_id': messageId,
              'user_id': currentUserId,
            });
      }
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }


  /// Marks all messages in a conversation as read by the current user
  Future<void> markAllMessagesAsRead(String conversationId) async {
    if (currentUserId == null) return;

    try {
      // Get all messages sent by the other user
      final unreadMessages = await _supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUserId!);

      if (unreadMessages.isEmpty) return;

      // Check which messages are already marked as read
      final messageIds = unreadMessages.map((msg) => msg['id']).toList();
      final existingReadStatus = await _supabase
          .from('message_read_status')
          .select('message_id')
          .eq('user_id', currentUserId!)
          .inFilter('message_id', messageIds);

      final alreadyReadIds = existingReadStatus
          .map((status) => status['message_id'])
          .toSet();

      // Only insert read status for messages that aren't already marked as read
      final readStatusInserts = unreadMessages
          .where((msg) => !alreadyReadIds.contains(msg['id']))
          .map((msg) => {
                'message_id': msg['id'],
                'user_id': currentUserId,
              })
          .toList();

      if (readStatusInserts.isNotEmpty) {
        await _supabase.from('message_read_status').insert(readStatusInserts);
      }
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  Future<DateTime?> getMessageReadTime(String messageId, String senderId, String recipientId) async {
    if (currentUserId == null) return null;

    // Only check read status for messages I sent
    if (senderId != currentUserId) return null;

    try {
      // Check if the recipient has read this message
      final readStatus = await _supabase
          .from('message_read_status')
          .select('read_at')
          .eq('message_id', messageId)
          .eq('user_id', recipientId)
          .maybeSingle();

      if (readStatus != null) {
        return DateTime.parse(readStatus['read_at']).toLocal();
        // print("message read at local time: ${localtime}");
      }

      return null;
    } catch (e) {
      print('Error getting message read time: $e');
      return null;
    }
  }

}