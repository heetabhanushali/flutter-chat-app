import 'dart:async';
import 'dart:math';
import 'package:chat_app/services/local_storage_service.dart';
import 'package:chat_app/services/connectivity_service.dart';
import 'package:chat_app/services/network_service.dart';

class MessageQueueService {
  // ── Singleton ──────────────────────────────────────────────
  static final MessageQueueService _instance = MessageQueueService._internal();
  factory MessageQueueService() => _instance;
  MessageQueueService._internal();
  // ──────────────────────────────────────────────────────────

  final LocalStorageService _localStorage = LocalStorageService();
  final ConnectivityService _connectivity = ConnectivityService();
  final NetworkService _network = NetworkService();

  // We can't import ChatService here (circular dependency)
  // Instead, we accept a send function
  Future<Map<String, dynamic>> Function({
    required String conversationId,
    required String content,
    required String clientMessageId,
  })? _sendFunction;

  bool _isProcessing = false;
  Timer? _retryTimer;
  StreamSubscription<bool>? _connectivitySub;
  bool _initialized = false;

  static const int _maxRetries = 5;

  // ── Stream for UI updates ──────────────────────────────────
  final StreamController<MessageStatusEvent> _statusController =
      StreamController<MessageStatusEvent>.broadcast();

  Stream<MessageStatusEvent> get statusUpdates => _statusController.stream;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  /// Call once at app startup. Provide the send function from ChatService.
  void initialize({
    required Future<Map<String, dynamic>> Function({
      required String conversationId,
      required String content,
      required String clientMessageId,
    }) sendFunction,
  }) {
    if (_initialized) return;
    _initialized = true;
    _sendFunction = sendFunction;

    // Listen to connectivity — process queue when back online
    _connectivitySub = _connectivity.onConnectivityChanged.listen((online) {
      if (online) {
        processQueue();
      }
    });

    // Process any leftover messages from last session
    if (_connectivity.isOnline) {
      processQueue();
    }
  }

  // ============================================================
  // ADD TO QUEUE
  // ============================================================

  Future<void> addToQueue({
    required String messageId,
    required String conversationId,
    required String content,
    required String senderId,
    required String clientMessageId,
  }) async {
    final pendingMessage = {
      'id': messageId,
      'conversation_id': conversationId,
      'content': content,
      'sender_id': senderId,
      'client_message_id': clientMessageId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'retry_count': 0,
      'next_retry_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
    };

    await _localStorage.addToQueue(pendingMessage);

    if (_connectivity.isOnline) {
      processQueue();
    }
  }

  // ============================================================
  // PROCESS QUEUE
  // ============================================================

  Future<void> processQueue() async {
    if (_isProcessing) return;
    if (!_connectivity.isOnline) return;
    if (_sendFunction == null) return;

    _isProcessing = true;

    try {
      final queuedMessages = _localStorage.getQueuedMessages();
      if (queuedMessages.isEmpty) return;

      for (final msg in queuedMessages) {
        if (!_connectivity.isOnline) break;

        final status = msg['status'];
        if (status == 'sending') continue;
        if (status == 'failed_permanent') continue;

        // Check retry timing
        final nextRetryStr = msg['next_retry_at'];
        if (nextRetryStr != null) {
          final nextRetryAt = DateTime.parse(nextRetryStr);
          if (DateTime.now().toUtc().isBefore(nextRetryAt)) continue;
        }

        await _sendQueuedMessage(msg);
      }
    } finally {
      _isProcessing = false;
    }

    _scheduleRetry();
  }

  Future<void> _sendQueuedMessage(Map<String, dynamic> msg) async {
    final messageId = msg['id'];
    final retryCount = msg['retry_count'] ?? 0;

    // Update to sending
    await _updateStatus(messageId, 'sending');

    try {
      final serverMessage = await _sendFunction!(
        conversationId: msg['conversation_id'],
        content: msg['content'],
        clientMessageId: msg['client_message_id'],
      );

      // Success — remove from queue, update local message
      await _localStorage.removeFromQueue(messageId);
      await _localStorage.replaceMessage(messageId, {
        ...serverMessage,
        'status': 'sent',
        'conversation_id': msg['conversation_id'],
      });

      _emitStatus(messageId, 'sent', serverMessage: serverMessage);
    } catch (e) {
      print('Failed to send queued message: $messageId — $e');

      // Non-retryable error — stop trying
      if (_network.isNonRetryableError(e)) {
        await _updateStatus(messageId, 'failed_permanent');
        print('Non-retryable error: $messageId');
        return;
      }

      final newRetryCount = retryCount + 1;

      if (newRetryCount >= _maxRetries) {
        await _updateStatus(messageId, 'failed');
      } else {
        final delaySeconds = pow(2, newRetryCount).toInt();
        final nextRetry = DateTime.now().toUtc().add(Duration(seconds: delaySeconds));

        await _localStorage.updateQueueItem(messageId, {
          'status': 'pending',
          'retry_count': newRetryCount,
          'next_retry_at': nextRetry.toIso8601String(),
        });
        await _localStorage.updateMessageStatus(messageId, 'pending');
        _emitStatus(messageId, 'pending');
      }
    }
  }

  // ============================================================
  // STATUS HELPERS
  // ============================================================

  Future<void> _updateStatus(String messageId, String status) async {
    await _localStorage.updateQueueItem(messageId, {'status': status});
    await _localStorage.updateMessageStatus(messageId, status);
    _emitStatus(messageId, status);
  }

  void _emitStatus(String messageId, String status, {Map<String, dynamic>? serverMessage}) {
    if (!_statusController.isClosed) {
      _statusController.add(MessageStatusEvent(
        messageId: messageId,
        status: status,
        serverMessage: serverMessage,
      ));
    }
  }

  // ============================================================
  // RETRY SCHEDULING
  // ============================================================

  void _scheduleRetry() {
    _retryTimer?.cancel();

    final queuedMessages = _localStorage.getQueuedMessages();
    final retryable = queuedMessages
        .where((m) => m['status'] == 'pending' || m['status'] == 'failed')
        .toList();

    if (retryable.isEmpty) return;

    DateTime? earliest;
    for (final msg in retryable) {
      final nextRetryStr = msg['next_retry_at'];
      if (nextRetryStr == null) continue;
      final nextRetry = DateTime.parse(nextRetryStr);
      if (earliest == null || nextRetry.isBefore(earliest)) {
        earliest = nextRetry;
      }
    }

    if (earliest != null) {
      final delay = earliest.difference(DateTime.now().toUtc());
      final actualDelay = delay.isNegative ? Duration.zero : delay;

      _retryTimer = Timer(actualDelay + const Duration(milliseconds: 500), () {
        if (_connectivity.isOnline) {
          processQueue();
        }
      });
    }
  }

  // ============================================================
  // MANUAL RETRY
  // ============================================================

  Future<void> retryMessage(String messageId) async {
    await _localStorage.updateQueueItem(messageId, {
      'status': 'pending',
      'retry_count': 0,
      'next_retry_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _localStorage.updateMessageStatus(messageId, 'pending');
    _emitStatus(messageId, 'pending');
    processQueue();
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  void dispose() {
    _retryTimer?.cancel();
    _connectivitySub?.cancel();
    _statusController.close();
    _initialized = false;
  }

  Future<void> clearQueue() async {
    _retryTimer?.cancel();
    await _localStorage.clearQueue();
  }
}

// ============================================================
// EVENT CLASS
// ============================================================

class MessageStatusEvent {
  final String messageId;
  final String status;
  final Map<String, dynamic>? serverMessage;

  MessageStatusEvent({
    required this.messageId,
    required this.status,
    this.serverMessage,
  });
}