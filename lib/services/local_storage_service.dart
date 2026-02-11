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

  bool _initialized = false;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  Future<void> init() async {
    if (_initialized) return;
    await Hive.openBox<Map>(_messagesBox);
    await Hive.openBox<Map>(_conversationsBox);
    await Hive.openBox<Map>(_pendingQueueBox);
    _initialized = true;
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  /// Save a single message
  Future<void> saveMessage(Map<String, dynamic> message) async {
    final box = Hive.box<Map>(_messagesBox);
    final id = message['id'];
    await box.put(id, Map<String, dynamic>.from(message));
  }

  /// Save a list of messages for a conversation (replaces existing)
  Future<void> saveMessages(String conversationId, List<Map<String, dynamic>> messages) async {
    final box = Hive.box<Map>(_messagesBox);

    // Remove old messages for this conversation
    final keysToRemove = <dynamic>[];
    for (final key in box.keys) {
      final msg = box.get(key);
      if (msg != null && msg['conversation_id'] == conversationId) {
        // Keep pending/failed messages — don't delete those
        final status = msg['status'];
        if (status == 'pending' || status == 'sending' || status == 'failed') {
          continue;
        }
        keysToRemove.add(key);
      }
    }
    await box.deleteAll(keysToRemove);

    // Save new messages
    for (final msg in messages) {
      final id = msg['id'];
      await box.put(id, Map<String, dynamic>.from({
        ...msg,
        'conversation_id': conversationId,
      }));
    }
  }

  /// Get all messages for a conversation, sorted by time
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

  /// Update status of a message
  Future<void> updateMessageStatus(String messageId, String status) async {
    final box = Hive.box<Map>(_messagesBox);
    final msg = box.get(messageId);
    if (msg != null) {
      final updated = Map<String, dynamic>.from(msg);
      updated['status'] = status;
      await box.put(messageId, updated);
    }
  }

  /// Replace a message (e.g., temp → server confirmed)
  Future<void> replaceMessage(String oldId, Map<String, dynamic> newMessage) async {
    final box = Hive.box<Map>(_messagesBox);
    await box.delete(oldId);
    await box.put(newMessage['id'], Map<String, dynamic>.from(newMessage));
  }

  /// Delete a single message
  Future<void> deleteMessage(String messageId) async {
    final box = Hive.box<Map>(_messagesBox);
    await box.delete(messageId);
  }

  // ============================================================
  // CONVERSATIONS
  // ============================================================

  /// Save conversations list (replaces all)
  Future<void> saveConversations(List<Map<String, dynamic>> conversations) async {
    final box = Hive.box<Map>(_conversationsBox);
    await box.clear();
    for (final conv in conversations) {
      await box.put(conv['id'], Map<String, dynamic>.from(conv));
    }
  }

  /// Get all conversations, sorted newest first
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
  // PENDING QUEUE
  // ============================================================

  /// Add a message to the pending send queue
  Future<void> addToQueue(Map<String, dynamic> pendingMessage) async {
    final box = Hive.box<Map>(_pendingQueueBox);
    final id = pendingMessage['id'];
    await box.put(id, Map<String, dynamic>.from(pendingMessage));
  }

  /// Get all queued messages, sorted by time
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

  /// Update fields on a queued message
  Future<void> updateQueueItem(String messageId, Map<String, dynamic> updates) async {
    final box = Hive.box<Map>(_pendingQueueBox);
    final msg = box.get(messageId);
    if (msg != null) {
      final updated = Map<String, dynamic>.from(msg);
      updated.addAll(updates);
      await box.put(messageId, updated);
    }
  }

  /// Remove a message from the queue (after successful send)
  Future<void> removeFromQueue(String messageId) async {
    final box = Hive.box<Map>(_pendingQueueBox);
    await box.delete(messageId);
  }

  /// Clear entire queue
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
  }
}