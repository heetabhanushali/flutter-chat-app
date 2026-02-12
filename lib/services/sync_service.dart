import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/services/local_storage_service.dart';
import 'package:chat_app/services/connectivity_service.dart';
import 'package:chat_app/services/network_service.dart';
import 'package:chat_app/services/encryption_service.dart';

// ============================================================
// SYNC EVENTS
// ============================================================

enum SyncEventType {
  conversationsUpdated,
  messagesUpdated,
  messageSent,
  messageFailed,
  syncStarted,
  syncCompleted,
  syncFailed,
}

class SyncEvent {
  final SyncEventType type;
  final String? conversationId;
  final String? messageId;
  final Map<String, dynamic>? data;

  SyncEvent({
    required this.type,
    this.conversationId,
    this.messageId,
    this.data,
  });
}

// ============================================================
// SYNC SERVICE
// ============================================================

class SyncService {
  // ── Singleton ──────────────────────────────────────────────
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();
  // ──────────────────────────────────────────────────────────

  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalStorageService _localStorage = LocalStorageService();
  final ConnectivityService _connectivity = ConnectivityService();
  final NetworkService _network = NetworkService();
  final EncryptionService _encryptionService = EncryptionService();

  String? get currentUserId => _supabase.auth.currentUser?.id;

  bool _initialized = false;
  bool _isSyncing = false;
  final Set<String> _syncingConversations = {};
  StreamSubscription<bool>? _connectivitySub;

  // ── Stream for UI updates ─────────────────────────────────
  final StreamController<SyncEvent> _syncController =
      StreamController<SyncEvent>.broadcast();

  Stream<SyncEvent> get syncUpdates => _syncController.stream;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _connectivitySub = _connectivity.onConnectivityChanged.listen((online) {
      if (online) {
        print('🔄 SyncService: Back online — starting sync');
        fullSync();
      }
    });

    // Initial sync if already online
    if (_connectivity.isOnline) {
      fullSync();
    }

    print('🔄 SyncService initialized');
  }

  // ============================================================
  // FULL SYNC
  // ============================================================

  Future<void> fullSync() async {
    if (_isSyncing) return;
    if (currentUserId == null) return;

    _isSyncing = true;
    _emit(SyncEventType.syncStarted);
    print('🔄 SyncService: Full sync started');

    try {
      await pushPendingMessages();
      await pushPendingDeletions();
      await syncConversations();

      _emit(SyncEventType.syncCompleted);
      print('🔄 SyncService: Full sync completed');
    } catch (e) {
      print('🔄 SyncService: Full sync failed — $e');
      _emit(SyncEventType.syncFailed);
    } finally {
      _isSyncing = false;
    }
  }

  // ============================================================
  // SYNC CONVERSATIONS (server → local)
  // ============================================================

  Future<void> syncConversations() async {
    if (currentUserId == null) return;

    try {
      final response = await _supabase.rpc(
        'get_user_conversations',
        params: {'p_user_id': currentUserId},
      );

      final List<Map<String, dynamic>> toCache = [];

      for (final conv in response) {
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

      _emit(SyncEventType.conversationsUpdated);
      print('🔄 SyncService: Conversations synced (${toCache.length})');
    } catch (e) {
      if (_network.isNetworkError(e)) {
        _network.reportOffline();
        print('🔄 SyncService: Cannot sync conversations — offline');
        return;
      }
      print('🔄 SyncService: Error syncing conversations — $e');
      rethrow;
    }
  }

  // ============================================================
  // SYNC MESSAGES (server → local)
  // ============================================================

  Future<void> syncMessages(String conversationId) async {
    if (currentUserId == null) return;

    // Prevent syncing the same conversation concurrently
    if (_syncingConversations.contains(conversationId)) return;
    _syncingConversations.add(conversationId);

    try {
      final conversation = await _supabase
          .from('conversations')
          .select('participant1_id, participant2_id')
          .eq('id', conversationId)
          .single();

      final recipientId = conversation['participant1_id'] == currentUserId
          ? conversation['participant2_id']
          : conversation['participant1_id'];

      // Get deletion time
      DateTime? deletedAt;
      try {
        final deletionResponse = await _supabase
            .from('user_deleted_conversations')
            .select('deleted_at')
            .eq('user_id', currentUserId!)
            .eq('conversation_id', conversationId)
            .maybeSingle();

        if (deletionResponse != null) {
          deletedAt = DateTime.parse(deletionResponse['deleted_at']).toUtc();
        }
      } catch (_) {}

      // Fetch messages
      final messages = await _supabase
          .from('messages')
          .select('*, sender:users!messages_sender_id_fkey(username, avatar_url)')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      // Filter by deletion time
      List<Map<String, dynamic>> filteredMessages;
      if (deletedAt != null) {
        final cutoff = deletedAt;
        filteredMessages = messages.where((msg) {
          final rawTime = msg['created_at'];
          DateTime msgTimeUtc;
          if (rawTime.toString().endsWith('Z') || rawTime.toString().contains('+')) {
            msgTimeUtc = DateTime.parse(rawTime);
          } else {
            msgTimeUtc = DateTime.parse('${rawTime}Z').toUtc();
          }
          return msgTimeUtc.isAfter(cutoff);
        }).toList();
      } else {
        filteredMessages = List<Map<String, dynamic>>.from(messages);
      }

      // Decrypt
      for (var msg in filteredMessages) {
        try {
          msg['content'] = await _encryptionService.decryptMessage(
            encryptedText: msg['content'],
            otherUserId: recipientId,
          );
        } catch (_) {
          msg['content'] = '[Unable to decrypt]';
        }
        msg['status'] = 'sent';
      }

      // Prepare for cache
      final messagesToCache = filteredMessages.map((msg) {
        final cached = Map<String, dynamic>.from(msg);
        cached['conversation_id'] = conversationId;
        if (cached['sender'] is Map) {
          cached['sender_username'] = cached['sender']['username'];
          cached['sender_avatar'] = cached['sender']['avatar_url'];
        }
        return cached;
      }).toList();

      // Save to local (preserves pending/sending/failed messages)
      await _localStorage.saveMessages(conversationId, messagesToCache);
      _network.reportOnline();

      _emit(SyncEventType.messagesUpdated, conversationId: conversationId);
      print('🔄 SyncService: Messages synced for $conversationId (${messagesToCache.length})');
    } catch (e) {
      if (_network.isNetworkError(e)) {
        _network.reportOffline();
        print('🔄 SyncService: Cannot sync messages — offline');
        return;
      }
      print('🔄 SyncService: Error syncing messages — $e');
      rethrow;
    } finally {
      _syncingConversations.remove(conversationId);
    }
  }

  // ============================================================
  // PUSH PENDING MESSAGES (local → server)
  // ============================================================

  Future<void> pushPendingMessages() async {
    if (currentUserId == null) return;

    final pendingMessages = _localStorage.getQueuedMessages();
    if (pendingMessages.isEmpty) {
      print('🔄 SyncService: No pending messages to push');
      return;
    }

    print('🔄 SyncService: Pushing ${pendingMessages.length} pending messages');

    for (final msg in pendingMessages) {
      final status = msg['status'];
      if (status == 'failed_permanent') continue;

      try {
        final clientMessageId = msg['client_message_id'];

        // Check if already sent (deduplication)
        final existing = await _supabase
            .from('messages')
            .select()
            .eq('client_message_id', clientMessageId)
            .maybeSingle();

        if (existing != null) {
          // Already on server — clean up local
          await _localStorage.removeFromQueue(msg['id']);
          await _localStorage.markMessageAsSent(msg['id'], {
            ...existing,
            'conversation_id': msg['conversation_id'],
            'status': 'sent',
          });
          _emit(
            SyncEventType.messageSent,
            messageId: msg['id'],
            conversationId: msg['conversation_id'],
            data: existing,
          );
          print('🔄 SyncService: Message already sent — ${msg['id']}');
          continue;
        }

        // Get recipient for encryption
        final conversation = await _supabase
            .from('conversations')
            .select('participant1_id, participant2_id')
            .eq('id', msg['conversation_id'])
            .single();

        final recipientId = conversation['participant1_id'] == currentUserId
            ? conversation['participant2_id']
            : conversation['participant1_id'];

        // Encrypt
        String messageToStore = msg['content'];
        try {
          messageToStore = await _encryptionService.encryptMessage(
            plainText: msg['content'],
            otherUserId: recipientId,
          );
        } catch (e) {
          print('🔄 SyncService: Encryption failed, sending unencrypted');
        }

        final now = DateTime.now().toUtc().toIso8601String();

        // Insert message on server
        final serverMessage = await _supabase.from('messages').insert({
          'conversation_id': msg['conversation_id'],
          'sender_id': currentUserId,
          'content': messageToStore,
          'created_at': now,
          'client_message_id': clientMessageId,
        }).select().single();

        // Update conversation on server
        await _supabase.from('conversations').update({
          'last_message': messageToStore,
          'updated_at': now,
        }).eq('id', msg['conversation_id']);

        // Clean up queue and update local message
        await _localStorage.removeFromQueue(msg['id']);
        await _localStorage.markMessageAsSent(msg['id'], {
          ...serverMessage,
          'conversation_id': msg['conversation_id'],
          'status': 'sent',
        });

        _emit(
          SyncEventType.messageSent,
          messageId: msg['id'],
          conversationId: msg['conversation_id'],
          data: serverMessage,
        );

        _network.reportOnline();
        print('🔄 SyncService: Message sent — ${msg['id']}');
      } catch (e) {
        if (_network.isNetworkError(e)) {
          _network.reportOffline();
          print('🔄 SyncService: Cannot push messages — offline');
          return; // Stop — we're offline
        }

        if (_network.isNonRetryableError(e)) {
          await _localStorage.updateQueueItem(msg['id'], {'status': 'failed_permanent'});
          await _localStorage.updateMessageStatus(msg['id'], 'failed_permanent');
          _emit(SyncEventType.messageFailed, messageId: msg['id']);
          print('🔄 SyncService: Message permanently failed — ${msg['id']}');
          continue;
        }

        // Retryable error — leave in queue for next sync
        print('🔄 SyncService: Message failed (will retry) — ${msg['id']}: $e');
      }
    }
  }

  // ============================================================
  // PUSH PENDING DELETIONS (local → server)
  // ============================================================

  Future<void> pushPendingDeletions() async {
    if (currentUserId == null) return;

    final deletedConversations = _localStorage.getDeletedConversations();
    if (deletedConversations.isEmpty) {
      print('🔄 SyncService: No pending deletions to push');
      return;
    }

    print('🔄 SyncService: Pushing ${deletedConversations.length} pending deletions');

    for (final deletion in deletedConversations) {
      try {
        final conversationId = deletion['conversation_id'];
        final deletedAt = deletion['deleted_at'];

        // Remove existing deletion record first
        await _supabase
            .from('user_deleted_conversations')
            .delete()
            .eq('user_id', currentUserId!)
            .eq('conversation_id', conversationId);

        // Insert new deletion record
        await _supabase.from('user_deleted_conversations').insert({
          'user_id': currentUserId,
          'conversation_id': conversationId,
          'deleted_at': deletedAt,
        });

        // Remove from local deleted list (sync confirmed)
        await _localStorage.removeFromDeleted(conversationId);

        _network.reportOnline();
        print('🔄 SyncService: Deletion synced — $conversationId');
      } catch (e) {
        if (_network.isNetworkError(e)) {
          _network.reportOffline();
          print('🔄 SyncService: Cannot push deletions — offline');
          return;
        }
        print('🔄 SyncService: Error pushing deletion — $e');
      }
    }
  }

  // ============================================================
  // FIRE-AND-FORGET TRIGGERS
  // ============================================================

  /// Trigger a full sync without awaiting. Safe to call from anywhere.
  void requestSync() {
    if (!_connectivity.isOnline) return;
    fullSync();
  }

  /// Trigger a message sync for one conversation without awaiting.
  void requestMessageSync(String conversationId) {
    if (!_connectivity.isOnline) return;
    syncMessages(conversationId);
  }

  // ============================================================
  // HELPERS
  // ============================================================

  void _emit(SyncEventType type, {String? conversationId, String? messageId, Map<String, dynamic>? data}) {
    if (!_syncController.isClosed) {
      _syncController.add(SyncEvent(
        type: type,
        conversationId: conversationId,
        messageId: messageId,
        data: data,
      ));
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  void dispose() {
    _connectivitySub?.cancel();
    _syncController.close();
    _initialized = false;
    _isSyncing = false;
    _syncingConversations.clear();
  }
}