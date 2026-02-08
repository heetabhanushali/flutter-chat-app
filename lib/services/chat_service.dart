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

  Future<List<Map<String, dynamic>>> loadConversations() async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Step 1: Get all deleted conversations for current user
      final deletedConversations = await _getDeletedConversationsMap();

      // Step 2: Get all conversations where user is a participant
      final allConversations = await _getAllUserConversations();

      // Step 3: Filter and process conversations
      final List<Map<String, dynamic>> result = [];

      for (final conv in allConversations) {
        final conversationId = conv['id'];

        if (deletedConversations.containsKey(conversationId)) {
          // Conversation was deleted - check if there are new messages
          final deletedAtUtc = deletedConversations[conversationId]!;
          final hasNewMessages = await _hasMessagesAfterDeletion(conversationId, deletedAtUtc);

          if (hasNewMessages) {
            final processedConv = _processConversation(conv);
            result.add(processedConv);
          }
        } else {
          // Conversation not deleted - include it
          final processedConv = _processConversation(conv);
          result.add(processedConv);
        }
      }

      return result;
    } catch (e) {
      print('Error loading conversations: $e');
      rethrow;
    }
  }

  /// Helper: Get deleted conversations as a Map
  Future<Map<String, DateTime>> _getDeletedConversationsMap() async {
    final response = await _supabase
        .from('user_deleted_conversations')
        .select('conversation_id, deleted_at')
        .eq('user_id', currentUserId!);

    final Map<String, DateTime> deletedConversations = {};
    for (final deleted in response) {
      deletedConversations[deleted['conversation_id']] =
          DateTime.parse(deleted['deleted_at']).toUtc();
    }

    // print("getDeletedConversationsMap: $deletedConversations");
    return deletedConversations;
  }

  /// Helper: Get all conversations where current user is a participant
  Future<List<Map<String, dynamic>>> _getAllUserConversations() async {
    final response = await _supabase
        .from('conversations')
        .select('''
          *,
          participant1:users!participant1_id(id, username, avatar_url),
          participant2:users!participant2_id(id, username, avatar_url)
        ''')
        .or('participant1_id.eq.$currentUserId,participant2_id.eq.$currentUserId')
        .order('updated_at', ascending: false);

    // print("getallUserConversations: ${response.length} Conversations");
    return List<Map<String, dynamic>>.from(response);
  }

  /// Helper: Check if there are messages after deletion time
  Future<bool> _hasMessagesAfterDeletion(String conversationId, DateTime deletedAtUtc) async {
    final messagesAfterDeletion = await _supabase
        .from('messages')
        .select('id, created_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(5);

    final validMessages = messagesAfterDeletion.where((msg) {
      final msgTime = DateTime.parse(msg['created_at'] + 'Z').toUtc();
      return msgTime.isAfter(deletedAtUtc);
    }).toList();

    // print("has messages after deletion: ${validMessages.length} found");
    // print("first valid message time: ${validMessages.isNotEmpty? DateTime.parse(validMessages.first['created_at'] + 'Z').toUtc() : 'none'}");
    // print("comparison of ${deletedAtUtc} with ${validMessages.isNotEmpty? DateTime.parse(validMessages.first['created_at'] + 'Z').toUtc() : 'none'}");
    return validMessages.isNotEmpty;
  }

  /// Helper: Process conversation to extract other user info
  Map<String, dynamic> _processConversation(Map<String, dynamic> conv) {
    final isParticipant1 = conv['participant1_id'] == currentUserId;
    final otherUser = isParticipant1 ? conv['participant2'] : conv['participant1'];

    return {
      'id': conv['id'],
      'otherUser': otherUser,
      'lastMessage': conv['last_message'] ?? '',
      'updatedAt': conv['updated_at'],
    };
  }

  /// Check if a conversation has unread messages
  Future<bool> isConversationUnread(String conversationId) async {
    if (currentUserId == null) return false;

    try {
      // Get the latest message in this conversation
      final latestMessage = await _supabase
          .from('messages')
          .select('id, sender_id, created_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (latestMessage == null) return false;

      // If current user sent the latest message, it's not unread for them
      if (latestMessage['sender_id'] == currentUserId) return false;

      // Check if current user has read this message
      final readStatus = await _supabase
          .from('message_read_status')
          .select('id')
          .eq('message_id', latestMessage['id'])
          .eq('user_id', currentUserId!)
          .maybeSingle();

      // If no read status exists, the message is unread
      return readStatus == null;
    } catch (e) {
      print('Error checking read status: $e');
      return false;
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