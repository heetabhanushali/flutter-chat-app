import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/services/encryption_service.dart';
import 'package:chat_app/services/local_storage_service.dart';
import 'package:chat_app/services/message_queue_service.dart';
import 'package:chat_app/services/network_service.dart';
import 'package:uuid/uuid.dart';

class ChatService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final EncryptionService _encryptionService = EncryptionService();
  final LocalStorageService _localStorage = LocalStorageService();
  final NetworkService _network = NetworkService();
  final Uuid _uuid = const Uuid();
  String? get currentUserId => _supabase.auth.currentUser?.id;
  bool _queueInitialized = false;

  void initQueue() {
    if (_queueInitialized) return;
    _queueInitialized = true;
    MessageQueueService().initialize(
      sendFunction: sendMessageFromQueue,
    );
  }

  // ===============================================
  // Deletion
  // ===============================================

  Future<bool> deleteConversationForUser(String conversationId) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    if (!_network.isOnline){
      throw Exception('Cannot delete conversation while offline');
    }

    try {
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

      return true;
    } catch (e) {
      print('Error deleting conversation: $e');
      rethrow;
    }
  }

  Future<DateTime?> getConversationDeletionTime(String conversationId) async {
    if (currentUserId == null) return null;
    if (!_network.isOnline) return null;

    try {
      final response = await _supabase
          .from('user_deleted_conversations')
          .select('deleted_at')
          .eq('user_id', currentUserId!)
          .eq('conversation_id', conversationId)
          .maybeSingle();

      if (response != null) {
        return DateTime.parse(response['deleted_at']).toUtc();
      }

      return null;
    } catch (e) {
      if (_network.isNetworkError(e)) {
        _network.reportOffline();
        return null;
      }
      print('Error getting conversation deletion time: $e');
      return null;
    }
  }

  // ===============================================
  // CONVERSATION MANAGEMENT
  // ===============================================

  /// Fetches all conversations for the current user using RPC
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
      final List<Map<String, dynamic>> toCache = [];

      for (final conv in response) {
        // Decrypt last message
        String lastMessage = conv['last_message'] ?? '';

        if (lastMessage.isNotEmpty) {
          try {
            lastMessage = await _encryptionService.decryptMessage(
              encryptedText: lastMessage,
              otherUserId: conv['other_user_id'],
            );
          } catch (_) {
            lastMessage = '[Encrypted Message]';
          }
        }

        result.add({
          'id': conv['conversation_id'],
          'otherUser': {
            'id': conv['other_user_id'],
            'username': conv['other_user_username'],
            'avatar_url': conv['other_user_avatar_url'],
          },
          'lastMessage': lastMessage,
          'updatedAt': conv['updated_at'],
          'isUnread': conv['is_unread'] ?? false,
        });

        toCache.add({
          'id': conv['conversation_id'],
          'otherUserId': conv['other_user_id'],
          'otherUsername': conv['other_user_username'],
          'otherAvatarUrl': conv['other_user_avatar_url'],
          'lastMessage': lastMessage,
          'updatedAt': conv['updated_at'],
          'isUnread': conv['is_unread'] ?? false,
        });
      }

      await _localStorage.saveConversations(toCache);
      _network.reportOnline();

      return result;
    } catch (e) {
      if (_network.isNetworkError(e)) {
        _network.reportOffline();

        final cached = _localStorage.getConversations();
        return cached.map((conv) => {
          'id': conv['id'],
          'otherUser': {
            'id': conv['otherUserId'],
            'username': conv['otherUsername'],
            'avatar_url': conv['otherAvatarUrl'],
          },
          'lastMessage': conv['lastMessage'],
          'updatedAt': conv['updatedAt'],
          'isUnread': conv['isUnread'] ?? false,
        }).toList();
      }
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
      _network.reportOnline();
      return conversationId;
    } catch (e) {
      if (_network.isNetworkError(e)) {
        _network.reportOffline();

        // Try to find conversation ID from cached conversations
        final cached = _localStorage.getConversations();
        for (final conv in cached) {
          if (conv['otherUserId'] == recipientId) {
            return conv['id'];
          }
        }
        return null;
      }
      print('Error getting existing conversation: $e');
      rethrow;
    }
  }

  Future<String?> getOrCreateConversation(String recipientId) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    if (!_network.isOnline) return null;

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
      final conversation = await _supabase
          .from('conversations')
          .select('participant1_id, participant2_id')
          .eq('id', conversationId)
          .single();

      final recipientId = conversation['participant1_id'] == currentUserId
          ? conversation['participant2_id']
          : conversation['participant1_id'];

      final deletedAt = await getConversationDeletionTime(conversationId);

      final messages = await _supabase
          .from('messages')
          .select('*, sender:users!messages_sender_id_fkey(username, avatar_url)')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      List<Map<String, dynamic>> filteredMessages;
      if (deletedAt != null) {
        filteredMessages = messages.where((msg) {
          final rawTime = msg['created_at'];
          DateTime msgTimeUtc;

          if (rawTime.toString().endsWith('Z') || rawTime.toString().contains('+')) {
            msgTimeUtc = DateTime.parse(rawTime);
          } else {
            msgTimeUtc = DateTime.parse(rawTime + 'Z').toUtc();
          }

          return msgTimeUtc.isAfter(deletedAt);
        }).toList();
      } else {
        filteredMessages = List<Map<String, dynamic>>.from(messages);
      }

      for (var msg in filteredMessages) {
        try {
          msg['content'] = await _encryptionService.decryptMessage(
            encryptedText: msg['content'],
            otherUserId: recipientId,
          );
        } catch (e) {
          print('Failed to decrypt message ${msg['id']}: $e');
          msg['content'] = '[Unable to decrypt]';
        }
        msg['status'] = 'sent';
      }

      final messagesToCache = filteredMessages.map((msg) {
        final cached = Map<String, dynamic>.from(msg);
        cached['conversation_id'] = conversationId;
        if (cached['sender'] is Map) {
          cached['sender_username'] = cached['sender']['username'];
          cached['sender_avatar'] = cached['sender']['avatar_url'];
        }
        return cached;
      }).toList();
      await _localStorage.saveMessages(conversationId, messagesToCache);
      _network.reportOnline();

      return filteredMessages;
    } catch (e) {
      if (_network.isNetworkError(e)) {
        _network.reportOffline();

        final cached = _localStorage.getMessages(conversationId);
        return cached.map((msg) {
          final message = Map<String, dynamic>.from(msg);
          if (message['sender'] == null) {
            message['sender'] = {
              'username': message['sender_username'] ?? 'Unknown',
              'avatar_url': message['sender_avatar'],
            };
          }
          return message;
        }).toList();
      }
      print('Error loading messages: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendMessage({
    required String conversationId,
    required String content,
    String? clientMessageId,
  }) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }
    initQueue();

    final msgClientId = clientMessageId ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final tempId = 'temp_$msgClientId';

    try {
      // ------ ONLINE PATH ---------------------------------
      final conversation = await _supabase
          .from('conversations')
          .select('participant1_id, participant2_id')
          .eq('id', conversationId)
          .single();

      final recipientId = conversation['participant1_id'] == currentUserId
          ? conversation['participant2_id']
          : conversation['participant1_id'];

      String messageToStore = content;
      String lastMessageToStore = content;

      try {
        messageToStore = await _encryptionService.encryptMessage(
          plainText: content,
          otherUserId: recipientId,
        );
        lastMessageToStore = messageToStore;
      } catch (e) {
        print('Encryption failed, sending unencrypted: $e');
      }

      final message = await _supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': currentUserId,
        'content': messageToStore,
        'created_at': now,
      }).select().single();

      await _supabase.from('conversations').update({
        'last_message': lastMessageToStore,
        'updated_at': now,
      }).eq('id', conversationId);

      _network.reportOnline();

      return {
        ...message,
        'status': 'sent',
        'client_message_id': msgClientId,
      };
    } catch (e) {
      // ---------- OFFLINE PATH ----------------
      if (_network.isNetworkError(e)){
        _network.reportOffline();

        await MessageQueueService().addToQueue(
          messageId: tempId,
          conversationId: conversationId,
          content: content,
          senderId: currentUserId!,
          clientMessageId: msgClientId,
        );
        await _localStorage.saveMessage({
          'id': tempId,
          'conversation_id': conversationId,
          'sender_id': currentUserId,
          'content': content,
          'created_at': now,
          'client_message_id': msgClientId,
          'status': 'pending',
        });
        await _localStorage.updateConversationLastMessage(conversationId, content);
        return {
          'id': tempId,
          'conversation_id': conversationId,
          'sender_id': currentUserId,
          'content': content,
          'created_at': now,
          'client_message_id': msgClientId,
          'status': 'pending',
        };
      }
      print('Error sending message: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendMessageFromQueue({
    required String conversationId,
    required String content,
    required String clientMessageId,
  }) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final now = DateTime.now().toUtc().toIso8601String();

    final existing = await _supabase
        .from('messages')
        .select()
        .eq('client_message_id', clientMessageId)
        .maybeSingle();

    if (existing != null) {
      return Map<String, dynamic>.from(existing);
    }

    final conversation = await _supabase
        .from('conversations')
        .select('participant1_id, participant2_id')
        .eq('id', conversationId)
        .single();

    final recipientId = conversation['participant1_id'] == currentUserId
        ? conversation['participant2_id']
        : conversation['participant1_id'];

    String messageToStore = content;
    String lastMessageToStore = content;

    try {
      messageToStore = await _encryptionService.encryptMessage(
        plainText: content,
        otherUserId: recipientId,
      );
      lastMessageToStore = messageToStore;
    } catch (e) {
      print('Encryption failed, sending unencrypted: $e');
    }

    final message = await _supabase.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': currentUserId,
      'content': messageToStore,
      'created_at': now,
      'client_message_id': clientMessageId,
    }).select().single();

    await _supabase.from('conversations').update({
      'last_message': lastMessageToStore,
      'updated_at': now,
    }).eq('id', conversationId);

    return message;
  }

  // ============================================================
  // READ STATUS MANAGEMENT
  // ============================================================

  Future<void> markConversationAsRead(String conversationId) async {
    if (currentUserId == null) return;
    if (!_network.isOnline) return;

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
    if (senderId == currentUserId) return;
    if (!_network.isOnline) return;

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
       if (e.toString().contains('23505') || e.toString().contains('duplicate key')) {
        return;
      }
      print('Error marking message as read: $e');
    }
  }


  /// Marks all messages in a conversation as read by the current user
  Future<void> markAllMessagesAsRead(String conversationId) async {
    if (currentUserId == null) return;
    if (!_network.isOnline) return;

    try {
      // Get all messages sent by the other user
      final unreadMessages = await _supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUserId!);

      if (unreadMessages.isEmpty) return;

      final messageIds = unreadMessages.map((msg) => msg['id']).toList();
      final existingReadStatus = await _supabase
          .from('message_read_status')
          .select('message_id')
          .eq('user_id', currentUserId!)
          .inFilter('message_id', messageIds);

      final alreadyReadIds = existingReadStatus
          .map((status) => status['message_id'])
          .toSet();

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
      if (e.toString().contains('23505') || e.toString().contains('duplicate key')) {
        return;
      }
      print('Error marking messages as read: $e');
    }
  }

  Future<DateTime?> getMessageReadTime(String messageId, String senderId, String recipientId) async {
    if (currentUserId == null) return null;
    if (senderId != currentUserId) return null;
    if (!_network.isOnline) return null;

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
      }

      return null;
    } catch (e) {
      if (_network.isNetworkError(e)) {
        _network.reportOffline();
        return null;
      }
      print('Error getting message read time: $e');
      return null;
    }
  }

}