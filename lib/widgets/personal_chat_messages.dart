import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/services/chat_service.dart';
import 'package:chat_app/services/user_service.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:chat_app/services/realtime_service.dart';
import 'package:chat_app/services/encryption_service.dart';

final supabase = Supabase.instance.client;

class PersonalChatMessages extends StatefulWidget {
  final String? conversationId;
  final Map<String, dynamic> recipientUser;

  const PersonalChatMessages({
    super.key,
    required this.conversationId,
    required this.recipientUser,
  });

  @override
  State<PersonalChatMessages> createState() => _PersonalChatMessagesState();
}

class _PersonalChatMessagesState extends State<PersonalChatMessages> {
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  RealtimeChannel? _messageSubscription;
  String? _error;
  Map<String, DateTime?> _messageReadStatusCache = {};
  RealtimeChannel? _readStatusSubscription;
  
  // Add these for better state management
  String? _currentConversationId;
  bool _hasLoadedOnce = false;
  DateTime? _deletionCutoffTime; 
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final RealtimeService _realtimeService = RealtimeService();
  final EncryptionService _encryptionService = EncryptionService();

  @override
  void initState() {
    super.initState();
    _currentConversationId = widget.conversationId;
    _loadMessages();
    _setupRealtimeSubscription();
  }

  @override
  @override
  void didUpdateWidget(PersonalChatMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.conversationId != widget.conversationId) {
      // If we already set the conversation ID via setConversationId,
      // don't reset everything
      if (_currentConversationId == widget.conversationId) {
        return;
      }
      
      _currentConversationId = widget.conversationId;
      _hasLoadedOnce = false;
      _deletionCutoffTime = null;
      _messages.clear();
      _messageReadStatusCache.clear();
      _realtimeService.unsubscribe(_messageSubscription);
      _realtimeService.unsubscribe(_readStatusSubscription);
      _loadMessages();
      _setupRealtimeSubscription();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _realtimeService.unsubscribe(_messageSubscription);
    _realtimeService.unsubscribe(_readStatusSubscription);
    super.dispose();
  }

  Future<DateTime?> _getConversationDeletionTime() async {
    if (_deletionCutoffTime != null) {
      return _deletionCutoffTime;
    }

    if (_currentConversationId == null) return null;

    try{
      _deletionCutoffTime = await _chatService.getConversationDeletionTime(_currentConversationId!);
      return _deletionCutoffTime;
    } catch (e) {
      print('Error getting conversation deletion time: $e');
      return null;
    }
  }

  Future<DateTime?> _getMessageReadTime(String messageId, String senderId) async {
    // Check cache first
    if (_messageReadStatusCache.containsKey(messageId)) {
      return _messageReadStatusCache[messageId];
    }

    try {
      final recipientId = widget.recipientUser['id'];
      if (recipientId == null) return null;

      final readTime = await _chatService.getMessageReadTime(
        messageId,
        senderId,
        recipientId,
      );

      // Cache the result
      _messageReadStatusCache[messageId] = readTime;

      return readTime;
    } catch (e) {
      print('Error checking message read status: $e');
      return null;
    }
  }

  String _formatReadTime(DateTime readTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final readDate = DateTime(readTime.year, readTime.month, readTime.day);
    
    if (readDate.isAtSameMomentAs(today)) {
      // Check if it's very recent (within last 5 minutes)
      final difference = now.difference(readTime);
      if (difference.inMinutes < 1) {
        return 'Read now';
      }
      
      // Same day, show time
      final hour = readTime.hour.toString().padLeft(2, '0');
      final minute = readTime.minute.toString().padLeft(2, '0');
      return 'Read $hour:$minute';
    } else if (readDate.isAtSameMomentAs(yesterday)) {
      return 'Read yesterday';
    } else {
      // Different day, show date
      final day = readTime.day.toString().padLeft(2, '0');
      final month = readTime.month.toString().padLeft(2, '0');
      final year = readTime.year;
      return 'Read $day/$month/$year';
    }
  }

  Widget _buildMessageStatus(Map<String, dynamic> message) {
    final messageId = message['id'];
    final isTemp = messageId.toString().startsWith('temp_');
    final color = Colors.black.withOpacity(0.6);
    
    if (isTemp) {
      return Text(
        'Sending...',
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Check cache first for immediate response
    if (_messageReadStatusCache.containsKey(messageId)) {
      final readTime = _messageReadStatusCache[messageId];
      if (readTime != null) {
        return Text(
          _formatReadTime(readTime),
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontStyle: FontStyle.italic,
          ),
        );
      } else {
        return Text(
          'Sent',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontStyle: FontStyle.italic,
          ),
        );
      }
    }

    // For real messages, use FutureBuilder as fallback
    return FutureBuilder<DateTime?>(
      future: _getMessageReadTime(messageId, message['sender_id']),
      builder: (context, snapshot) {
        // While loading, show "Sent"
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text(
            'Sent',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontStyle: FontStyle.italic,
            ),
          );
        }
        
        // If there's an error, show "Sent"
        if (snapshot.hasError) {
          return Text(
            'Sent',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontStyle: FontStyle.italic,
            ),
          );
        }

        final readTime = snapshot.data;
        if (readTime != null) {
          return Text(
            _formatReadTime(readTime),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontStyle: FontStyle.italic,
            ),
          );
        } else {
          return Text(
            'Sent',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontStyle: FontStyle.italic,
            ),
          );
        }
      },
    );
  }

  bool _isLastMessageByMe(int index) {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return false;
    
    final currentMessage = _messages[index];
    if (currentMessage['sender_id'] != currentUserId) return false;
    
    // Check if there's any message after this one sent by current user
    for (int i = index + 1; i < _messages.length; i++) {
      if (_messages[i]['sender_id'] == currentUserId) {
        return false; // Found a newer message by current user
      }
    }
    
    return true; // This is the last message by current user
  }

  Future<void> _markMessageAsRead(String messageId, String senderId) async {
    try {
      await _chatService.markMessageAsRead(messageId, senderId);
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }

  Future<void> markAllExistingMessagesAsRead() async {
    if (_currentConversationId == null) return;

    try {
      await _chatService.markAllMessagesAsRead(_currentConversationId!);
    } catch (e) {
      print('Error marking existing messages as read: $e');
    }
  }

  Future<void> _loadMessages() async {
    if (_currentConversationId == null) return;
    if (_isLoading) return;

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Load messages from service
      final messages = await _chatService.loadMessages(_currentConversationId!);

      // Cache deletion time for later use
      _deletionCutoffTime = await _chatService.getConversationDeletionTime(_currentConversationId!);

      if (mounted && _currentConversationId == widget.conversationId) {
        setState(() {
          _messages = messages;
          _isLoading = false;
          _hasLoadedOnce = true;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && messages.isNotEmpty) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
          markAllExistingMessagesAsRead();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load messages: ${e.toString()}';
        });
      }
    }
  }

  void _setupRealtimeSubscription() {
    if (_currentConversationId == null) return;

    // Clean up existing subscriptions
    _realtimeService.unsubscribe(_messageSubscription);
    _realtimeService.unsubscribe(_readStatusSubscription);

    // Subscribe to new messages
    _messageSubscription = _realtimeService.subscribeToMessages(
      conversationId: _currentConversationId!,
      onNewMessage: (messageData) {
        if (mounted) {
          _addNewMessage(messageData);
        }
      },
      onError: (error) {
        print('Message subscription error: $error');
      },
    );

    // Subscribe to read status changes
    final recipientId = widget.recipientUser['id'];
    if (recipientId != null) {
      _readStatusSubscription = _realtimeService.subscribeToReadStatus(
        recipientId: recipientId,
        onMessageRead: (messageId, readAt) {
          if (mounted) {
            _messageReadStatusCache[messageId] = readAt;
            setState(() {});
          }
        },
        messageExistsCheck: (messageId) {
          return _messages.any((msg) => msg['id'] == messageId);
        },
        onError: (error) {
          print('Read status subscription error: $error');
        },
      );
    }
  }

  void _addNewMessage(Map<String, dynamic> messageData) async {
    final currentUserId = _chatService.currentUserId;

    final messageExists = _messages.any((msg) => msg['id'] == messageData['id']);
    if (messageExists) {
      return;
    }

    final deletedAt = await _getConversationDeletionTime();
    if (deletedAt != null) {
      final rawTime = messageData['created_at'];
      DateTime messageTimeUtc;

      if (rawTime.toString().endsWith('Z') || rawTime.toString().contains('+')) {
        messageTimeUtc = DateTime.parse(rawTime);
      } else {
        messageTimeUtc = DateTime.parse(rawTime + 'Z').toUtc();
      }

      if (messageTimeUtc.isBefore(deletedAt) || messageTimeUtc.isAtSameMomentAs(deletedAt)) {
        return;
      }
    }

    try {
      messageData['content'] = await _encryptionService.decryptMessage(
        encryptedText: messageData['content'],
        otherUserId: widget.recipientUser['id'],
      );
    } catch (e) {
      print('Failed to decrypt realtime message: $e');
      messageData['content'] = '[Unable to decrypt]';
    }

    if (messageData['sender_id'] == currentUserId) {
      final tempMessageExists = _messages.any((msg) =>
        msg['sender_id'] == currentUserId &&
        msg['content'] == messageData['content'] &&
        msg['id'].toString().startsWith('temp_')
      );

      if (tempMessageExists) {
        setState(() {
          final index = _messages.indexWhere((msg) =>
            msg['sender_id'] == currentUserId &&
            msg['content'] == messageData['content'] &&
            msg['id'].toString().startsWith('temp_')
          );
          if (index != -1) {
            _messages[index] = {
              ...messageData,
              'sender': _messages[index]['sender'],
            };
          }
        });
        return;
      }
    }

    try {
      final senderResponse = await _userService.getUserInfo(messageData['sender_id']);

      final completeMessage = {
        ...messageData,
        'sender': senderResponse,
      };

      if (mounted && _currentConversationId == widget.conversationId) {
        setState(() {
          _messages.add(completeMessage);
        });

        _scrollToBottom();
        await _markMessageAsRead(messageData['id'], messageData['sender_id']);
      }
    } catch (e) {
      if (mounted && _currentConversationId == widget.conversationId) {
        setState(() {
          _messages.add({
            ...messageData,
            'sender': {'username': 'Unknown', 'avatar_url': null},
          });
        });
        _scrollToBottom();
        await _markMessageAsRead(messageData['id'], messageData['sender_id']);
      }
    }
  }

  void setConversationId(String? conversationId) {
    if (_currentConversationId == conversationId) return;
    
    _currentConversationId = conversationId;

    _realtimeService.unsubscribe(_messageSubscription);
    _realtimeService.unsubscribe(_readStatusSubscription);
    _setupRealtimeSubscription();
  }

  void addOptimisticMessage(Map<String, dynamic> message) {
    if (mounted) {
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();
    }
  }

  void updateOptimisticMessage(String tempId, Map<String, dynamic> realMessage) {
    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((msg) => msg['id'] == tempId);
        if (index != -1) {
          _messages[index] = realMessage;
        }
      });
    }
  }

  void removeOptimisticMessage(String tempId) {
    if (mounted) {
      setState(() {
        _messages.removeWhere((msg) => msg['id'] == tempId);
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _shouldShowTimestamp(int index) {
    if (index == 0) return true;
    
    final currentMessage = _messages[index];
    final previousMessage = _messages[index - 1];
    
    final currentRaw = currentMessage['created_at'].toString();
    final currentTime = currentRaw.endsWith('Z') || currentRaw.contains('+')
        ? DateTime.parse(currentRaw).toLocal()
        : DateTime.parse(currentRaw + 'Z').toLocal();

    final previousRaw = previousMessage['created_at'].toString();
    final previousTime = previousRaw.endsWith('Z') || previousRaw.contains('+')
        ? DateTime.parse(previousRaw).toLocal()
        : DateTime.parse(previousRaw + 'Z').toLocal();
    
    return !_isSameDay(currentTime , previousTime);
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
          date1.month == date2.month &&
          date1.day == date2.day;
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    if (messageDate.isAtSameMomentAs(today)) {
      return 'Today';
    } else if (messageDate.isAtSameMomentAs(yesterday)) {
      return 'Yesterday';
    } else {
      // For older dates, show the actual date
      final difference = today.difference(messageDate).inDays;
      if (difference < 7) {
        // Show day name for this week (Monday, Tuesday, etc.)
        const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        return weekdays[timestamp.weekday - 1];
      } else {
        // Show date for older messages (Aug 14, 2024)
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return '${months[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year}';
      }
    }
  }

  Widget _buildTimestampDivider(DateTime timestamp) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          SizedBox(width: 15.0,),
          Text(
            _formatTimestamp(timestamp),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 12.0)
          ),
          SizedBox(width: 15.0,),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipientName = widget.recipientUser['username'] ?? 'Unknown User';
    final recipientAvatarUrl = widget.recipientUser['avatar_url'];

    if (_error != null) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              const Text('Failed to load messages', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _error = null);
                  _loadMessages();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: _isLoading && !_hasLoadedOnce
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [

                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 109, 77, 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock,
                              size: 12,
                              color: const Color.fromRGBO(255, 109, 77, 0.8),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Messages are end-to-end encrypted. No one outside of this chat can read them.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: const Color.fromRGBO(255, 109, 77, 0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 200),

                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.blue[100],
                        backgroundImage: recipientAvatarUrl != null 
                            ? NetworkImage(recipientAvatarUrl) 
                            : null,
                        child: recipientAvatarUrl == null 
                            ? Icon(Icons.person, color: Colors.blue[700], size: 40)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(recipientName, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      const Text('Start a conversation', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: _messages.length + 1,
                  itemBuilder: (context, index) {
                    
                    if (index == 0) {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                        margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 109, 77, 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock,
                              size: 12,
                              color: const Color.fromRGBO(255, 109, 77, 0.8),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Messages are end-to-end encrypted. No one outside of this chat can read them.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: const Color.fromRGBO(255, 109, 77, 0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final messageIndex = index - 1;
                    final message = _messages[messageIndex];
                    final rawTime = message['created_at'].toString();
                    final timestamp = rawTime.endsWith('Z') || rawTime.contains('+')
                                      ? DateTime.parse(rawTime).toLocal()
                                      : DateTime.parse(rawTime + 'Z').toLocal();
                    final isMe = message['sender_id'] == _chatService.currentUserId;
                    
                    return Column(
                      children: [
                        if (_shouldShowTimestamp(messageIndex))
                          _buildTimestampDivider(timestamp),
                        MessageBubble(
                          content: message['content'] ?? '', 
                          timestamp: timestamp, 
                          isMe: isMe,
                          statusWidget: isMe && _isLastMessageByMe(messageIndex) ? _buildMessageStatus(message) : null,
                        )
                      ],
                    );
                  },
                ),
    );
  }
}