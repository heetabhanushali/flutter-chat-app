import 'package:hive/hive.dart';

class LocalStorageService {
  // ── Singleton ──────────────────────────────────────────────
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();
  // ──────────────────────────────────────────────────────────

  static const _messagesBox = 'cached_messages';
  static const _conversationsBox = 'cached_conversations';
  static const _pendingQueueBox = 'pending_queue';
  static const _deletedConversationsBox = 'deleted_conversations'; 

  bool _initialized = false;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  Future<void> init() async {
    if (_initialized) return;
    await Hive.openBox<Map>(_messagesBox);
    await Hive.openBox<Map>(_conversationsBox);
    await Hive.openBox<Map>(_pendingQueueBox);
    await Hive.openBox<Map>(_deletedConversationsBox); 
    _initialized = true;
  }

  // ============================================================
  // MESSAGES 
  // ============================================================

  Future<void> saveMessage(Map<String, dynamic> message) async {
    final box = Hive.box<Map>(_messagesBox);
    final id = message['id'];
    await box.put(id, Map<String, dynamic>.from(message));
  }

  Future<void> saveMessages(String conversationId, List<Map<String, dynamic>> messages) async {
    final box = Hive.box<Map>(_messagesBox);

    final keysToRemove = <dynamic>[];
    for (final key in box.keys) {
      final msg = box.get(key);
      if (msg != null && msg['conversation_id'] == conversationId) {
        final status = msg['status'];
        if (status == 'pending' || status == 'sending' || status == 'failed') {
          continue;
        }
        keysToRemove.add(key);
      }
    }
    await box.deleteAll(keysToRemove);

    for (final msg in messages) {
      final id = msg['id'];
      await box.put(id, Map<String, dynamic>.from({
        ...msg,
        'conversation_id': conversationId,
      }));
    }
  }

  List<Map<String, dynamic>> getMessages(String conversationId) {
    if (!Hive.isBoxOpen(_messagesBox)) return [];
    final box = Hive.box<Map>(_messagesBox);
    final messages = <Map<String, dynamic>>[];

    for (final key in box.keys) {
      final msg = box.get(key);
      if (msg != null && msg['conversation_id'] == conversationId) {
        messages.add(Map<String, dynamic>.from(msg));
      }
    }

    messages.sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      return aTime.compareTo(bTime);
    });

    return messages;
  }

  Future<void> updateMessageStatus(String messageId, String status) async {
    final box = Hive.box<Map>(_messagesBox);
    final msg = box.get(messageId);
    if (msg != null) {
      final updated = Map<String, dynamic>.from(msg);
      updated['status'] = status;
      await box.put(messageId, updated);
    }
  }

  Future<void> replaceMessage(String oldId, Map<String, dynamic> newMessage) async {
    final box = Hive.box<Map>(_messagesBox);
    await box.delete(oldId);
    await box.put(newMessage['id'], Map<String, dynamic>.from(newMessage));
  }

  Future<void> deleteMessage(String messageId) async {
    final box = Hive.box<Map>(_messagesBox);
    await box.delete(messageId);
  }

  // ============================================================
  // MESSAGES 
  // ============================================================

  List<Map<String, dynamic>> getPendingMessages(String conversationId) {
    if (!Hive.isBoxOpen(_messagesBox)) return [];
    final box = Hive.box<Map>(_messagesBox);
    final messages = <Map<String, dynamic>>[];

    for (final key in box.keys) {
      final msg = box.get(key);
      if (msg == null) continue;
      if (msg['conversation_id'] != conversationId) continue;

      final status = msg['status'];
      if (status == 'pending' || status == 'sending' || status == 'failed') {
        messages.add(Map<String, dynamic>.from(msg));
      }
    }

    messages.sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      return aTime.compareTo(bTime);
    });

    return messages;
  }

  List<Map<String, dynamic>> getAllPendingMessages() {
    if (!Hive.isBoxOpen(_messagesBox)) return [];
    final box = Hive.box<Map>(_messagesBox);
    final messages = <Map<String, dynamic>>[];

    for (final key in box.keys) {
      final msg = box.get(key);
      if (msg == null) continue;

      final status = msg['status'];
      if (status == 'pending' || status == 'sending' || status == 'failed') {
        messages.add(Map<String, dynamic>.from(msg));
      }
    }

    messages.sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      return aTime.compareTo(bTime);
    });

    return messages;
  }

  Future<void> markMessageAsSent(String tempId, Map<String, dynamic> serverMessage) async {
    final box = Hive.box<Map>(_messagesBox);
    await box.delete(tempId);
    final message = Map<String, dynamic>.from(serverMessage);
    message['status'] = 'sent';
    await box.put(message['id'], message);
  }

  // ============================================================
  // CONVERSATIONS 
  // ============================================================

  Future<void> saveConversations(List<Map<String, dynamic>> conversations) async {
    final box = Hive.box<Map>(_conversationsBox);
    await box.clear();
    for (final conv in conversations) {
      await box.put(conv['id'], Map<String, dynamic>.from(conv));
    }
  }

  List<Map<String, dynamic>> getConversations() {
    if (!Hive.isBoxOpen(_conversationsBox)) return [];
    final box = Hive.box<Map>(_conversationsBox);
    final conversations = <Map<String, dynamic>>[];

    for (final key in box.keys) {
      final conv = box.get(key);
      if (conv != null) {
        conversations.add(Map<String, dynamic>.from(conv));
      }
    }

    conversations.sort((a, b) {
      final aTime = a['updatedAt']?.toString() ?? '';
      final bTime = b['updatedAt']?.toString() ?? '';
      return bTime.compareTo(aTime);
    });

    return conversations;
  }

  Future<void> updateConversationLastMessage(String conversationId, String lastMessage) async {
    if (!Hive.isBoxOpen(_conversationsBox)) return;
    final box = Hive.box<Map>(_conversationsBox);
    final conv = box.get(conversationId);
    if (conv != null) {
      final updated = Map<String, dynamic>.from(conv);
      updated['lastMessage'] = lastMessage;
      updated['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      await box.put(conversationId, updated);
    }
  }

  // ============================================================
  // CONVERSATIONS
  // ============================================================

  Map<String, dynamic>? getConversation(String conversationId) {
    if (!Hive.isBoxOpen(_conversationsBox)) return null;
    final box = Hive.box<Map>(_conversationsBox);
    final conv = box.get(conversationId);
    if (conv != null) {
      return Map<String, dynamic>.from(conv);
    }
    return null;
  }

  Future<void> updateConversation(String conversationId, Map<String, dynamic> updates) async {
    if (!Hive.isBoxOpen(_conversationsBox)) return;
    final box = Hive.box<Map>(_conversationsBox);
    final conv = box.get(conversationId);
    if (conv != null) {
      final updated = Map<String, dynamic>.from(conv);
      updated.addAll(updates);
      await box.put(conversationId, updated);
    }
  }

  Future<void> removeConversation(String conversationId) async {
    if (!Hive.isBoxOpen(_conversationsBox)) return;
    final box = Hive.box<Map>(_conversationsBox);
    await box.delete(conversationId);
  }

  // ============================================================
  // DELETED CONVERSATIONS 
  // ============================================================

  Future<void> markConversationAsDeleted(String conversationId) async {
    final box = Hive.box<Map>(_deletedConversationsBox);
    await box.put(conversationId, {
      'conversation_id': conversationId,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  List<String> getDeletedConversationIds() {
    if (!Hive.isBoxOpen(_deletedConversationsBox)) return [];
    final box = Hive.box<Map>(_deletedConversationsBox);
    return box.keys.cast<String>().toList();
  }

  List<Map<String, dynamic>> getDeletedConversations() {
    if (!Hive.isBoxOpen(_deletedConversationsBox)) return [];
    final box = Hive.box<Map>(_deletedConversationsBox);
    final result = <Map<String, dynamic>>[];

    for (final key in box.keys) {
      final entry = box.get(key);
      if (entry != null) {
        result.add(Map<String, dynamic>.from(entry));
      }
    }

    return result;
  }

  Map<String, dynamic>? getConversationDeletion(String conversationId) {
    if (!Hive.isBoxOpen(_deletedConversationsBox)) return null;
    final box = Hive.box<Map>(_deletedConversationsBox);
    final entry = box.get(conversationId);
    if (entry != null) {
      return Map<String, dynamic>.from(entry);
    }
    return null;
  }

  Future<void> removeFromDeleted(String conversationId) async {
    if (!Hive.isBoxOpen(_deletedConversationsBox)) return;
    final box = Hive.box<Map>(_deletedConversationsBox);
    await box.delete(conversationId);
  }

  // ============================================================
  // PENDING QUEUE 
  // ============================================================

  Future<void> addToQueue(Map<String, dynamic> pendingMessage) async {
    final box = Hive.box<Map>(_pendingQueueBox);
    final id = pendingMessage['id'];
    await box.put(id, Map<String, dynamic>.from(pendingMessage));
  }

  List<Map<String, dynamic>> getQueuedMessages() {
    if (!Hive.isBoxOpen(_pendingQueueBox)) return [];
    final box = Hive.box<Map>(_pendingQueueBox);
    final messages = <Map<String, dynamic>>[];

    for (final key in box.keys) {
      final msg = box.get(key);
      if (msg != null) {
        messages.add(Map<String, dynamic>.from(msg));
      }
    }

    messages.sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      return aTime.compareTo(bTime);
    });

    return messages;
  }

  Future<void> updateQueueItem(String messageId, Map<String, dynamic> updates) async {
    final box = Hive.box<Map>(_pendingQueueBox);
    final msg = box.get(messageId);
    if (msg != null) {
      final updated = Map<String, dynamic>.from(msg);
      updated.addAll(updates);
      await box.put(messageId, updated);
    }
  }

  Future<void> removeFromQueue(String messageId) async {
    final box = Hive.box<Map>(_pendingQueueBox);
    await box.delete(messageId);
  }

  Future<void> clearQueue() async {
    final box = Hive.box<Map>(_pendingQueueBox);
    await box.clear();
  }

  // ============================================================
  // CLEANUP 
  // ============================================================

  Future<void> clearAll() async {
    if (Hive.isBoxOpen(_messagesBox)) await Hive.box<Map>(_messagesBox).clear();
    if (Hive.isBoxOpen(_conversationsBox)) await Hive.box<Map>(_conversationsBox).clear();
    if (Hive.isBoxOpen(_pendingQueueBox)) await Hive.box<Map>(_pendingQueueBox).clear();
    if (Hive.isBoxOpen(_deletedConversationsBox)) await Hive.box<Map>(_deletedConversationsBox).clear();
  }
}