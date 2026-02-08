import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  DateTime? _deletionCutoffTime; // Cache the deletion time

  @override
  void initState() {
    super.initState();
    _currentConversationId = widget.conversationId;
    _loadMessages();
    _setupRealtimeSubscription();
  }

  @override
  void didUpdateWidget(PersonalChatMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Only reload if conversation ID changed
    if (oldWidget.conversationId != widget.conversationId) {
      _currentConversationId = widget.conversationId;
      _hasLoadedOnce = false;
      _deletionCutoffTime = null;
      _messages.clear();
      _messageReadStatusCache.clear(); // Clear the cache
      _messageSubscription?.unsubscribe();
      _readStatusSubscription?.unsubscribe();
      _loadMessages();
      _setupRealtimeSubscription();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageSubscription?.unsubscribe();
    _readStatusSubscription?.unsubscribe();
    super.dispose();
  }

  Future<DateTime?> _getConversationDeletionTime() async {
    // Return cached value if available
    if (_deletionCutoffTime != null) {
      return _deletionCutoffTime;
    }

    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || _currentConversationId == null) return null;

    try {
      final deletionResponse = await supabase
          .from('user_deleted_conversations')
          .select('deleted_at')
          .eq('user_id', currentUserId)
          .eq('conversation_id', _currentConversationId!)
          .maybeSingle();

      if (deletionResponse != null) {
        _deletionCutoffTime = DateTime.parse(deletionResponse['deleted_at']).toUtc();
        return _deletionCutoffTime;
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<DateTime?> _getMessageReadTime(String messageId, String senderId) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return null;

    // Only check read status for messages I sent
    if (senderId != currentUserId) return null;

    // Check cache first
    if (_messageReadStatusCache.containsKey(messageId)) {
      return _messageReadStatusCache[messageId];
    }

    try {
      // Get the recipient's user ID from the widget
      final recipientId = widget.recipientUser['id'];
      if (recipientId == null) return null;

      // Check if the recipient has read this message and get the read_at timestamp
      final readStatus = await supabase
          .from('message_read_status')
          .select('read_at')
          .eq('message_id', messageId)
          .eq('user_id', recipientId)
          .maybeSingle();

      DateTime? readTime;
      if (readStatus != null) {
        readTime = DateTime.parse(readStatus['read_at']).toLocal();
      }
      
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
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || senderId == currentUserId) return;

    try {
      // Check if already marked as read
      final existingRead = await supabase
          .from('message_read_status')
          .select('id')
          .eq('message_id', messageId)
          .eq('user_id', currentUserId)
          .maybeSingle();

      // Only insert if not already marked as read
      if (existingRead == null) {
        await supabase
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

  Future<void> markAllExistingMessagesAsRead() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || _currentConversationId == null) return;

    try {
      // Get all messages in this conversation that were sent by the other user
      final unreadMessages = _messages.where((msg) => 
        msg['sender_id'] != currentUserId
      ).toList();

      if (unreadMessages.isEmpty) return;

      // Check which messages are already marked as read
      final messageIds = unreadMessages.map((msg) => msg['id']).toList();
      final existingReadStatus = await supabase
          .from('message_read_status')
          .select('message_id')
          .eq('user_id', currentUserId)
          .inFilter('message_id', messageIds);

      final alreadyReadIds = existingReadStatus.map((status) => status['message_id']).toSet();

      // Only insert read status for messages that aren't already marked as read
      final readStatusInserts = unreadMessages
          .where((msg) => !alreadyReadIds.contains(msg['id']))
          .map((msg) => {
            'message_id': msg['id'],
            'user_id': currentUserId,
          }).toList();

      if (readStatusInserts.isNotEmpty) {
        await supabase
            .from('message_read_status')
            .insert(readStatusInserts);
      }
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

      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Get deletion cutoff time
      final deletedAt = await _getConversationDeletionTime();

      final messages = await supabase
          .from('messages')
          .select('*, sender:users!messages_sender_id_fkey(username, avatar_url)')
          .eq('conversation_id', _currentConversationId!)
          .order('created_at', ascending: true);

      // Filter messages based on deletion time
      final filteredMessages = deletedAt != null 
        ? messages.where((msg) {
          final msgTimeUtc = DateTime.parse(msg['created_at'] + 'Z').toUtc();
          final isAfterDeletion = msgTimeUtc.isAfter(deletedAt);
          return isAfterDeletion;
        }).toList()
        : messages;

      if (mounted && _currentConversationId == widget.conversationId) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(filteredMessages);
          _isLoading = false;
          _hasLoadedOnce = true;
        });

        // Only scroll to bottom on initial load or if user was already at bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && filteredMessages.isNotEmpty) {
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
    _messageSubscription?.unsubscribe();
    _readStatusSubscription?.unsubscribe();

    // Subscribe to new messages
    _messageSubscription = supabase
        .channel('messages_${_currentConversationId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: _currentConversationId!,
          ),
          callback: (payload) {
            final newMessage = payload.newRecord;
            if (mounted) {
              _addNewMessage(newMessage);
            }
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            print('Message subscription error: $error');
          }
        });

    // Subscribe to read status changes
    _readStatusSubscription = supabase
        .channel('read_status_${_currentConversationId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_read_status',
          callback: (payload) {
            final newReadStatus = payload.newRecord;
            final messageId = newReadStatus['message_id'];
            final userId = newReadStatus['user_id'];
            final readAt = newReadStatus['read_at'];
            
            if (mounted && messageId != null && userId != null && readAt != null) {
              // Check if this read status is for a message in our current conversation
              // and if the user who read it is the recipient
              final recipientId = widget.recipientUser['id'];
              final messageExists = _messages.any((msg) => msg['id'] == messageId);
              
              if (messageExists && userId == recipientId) {
                // Update cache with the read timestamp
                _messageReadStatusCache[messageId] = DateTime.parse(readAt).toLocal();
                
                setState(() {
                  // This will cause the message status widgets to rebuild
                });
              }
            }
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            print('Read status subscription error: $error');
          }
        });
  }

  void _addNewMessage(Map<String, dynamic> messageData) async {
    final currentUserId = supabase.auth.currentUser?.id;
    
    // Check if message already exists (prevent duplicates)
    final messageExists = _messages.any((msg) => msg['id'] == messageData['id']);
    if (messageExists) {
      return;
    }

    // Check against deletion cutoff time
    final deletedAt = await _getConversationDeletionTime();
    if (deletedAt != null) {
      final messageTimeUtc = DateTime.parse(messageData['created_at'] + 'Z').toUtc();
      if (messageTimeUtc.isBefore(deletedAt) || messageTimeUtc.isAtSameMomentAs(deletedAt)) {
        return;
      }
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
              'sender': _messages[index]['sender'], // Keep existing sender info
            };
          }
        });
        return;
      }
    }

    try {
      // Fetch sender info for the new message
      final senderResponse = await supabase
          .from('users')
          .select('username, avatar_url')
          .eq('id', messageData['sender_id'])
          .single();

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
    
    final currentTime = DateTime.parse(currentMessage['created_at']);
    final previousTime = DateTime.parse(previousMessage['created_at']);
    
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

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isMe = message['sender_id'] == currentUserId;
    final content = message['content'] ?? '';
    final timestamp = DateTime.parse(message['created_at']);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: isMe ? 64 : 16,
          right: isMe ? 16 : 64,
        ),
        child: Column(
          crossAxisAlignment: isMe? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe 
                    ? const Color.fromRGBO(255, 109, 77, 1.0)
                    : Colors.grey[200],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    offset: const Offset(0, 1),
                    blurRadius: 3,
                    color: Colors.black.withOpacity(0.1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      content,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isMe ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isMe && _isLastMessageByMe(_messages.indexOf(message))) ...[
            // if (isMe)...[
              const SizedBox(width: 8),
              _buildMessageStatus(message),
            ],
          ],
        ),
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final timestamp = DateTime.parse(message['created_at']);
                    
                    return Column(
                      children: [
                        if (_shouldShowTimestamp(index))
                          _buildTimestampDivider(timestamp),
                        _buildMessageBubble(message),
                      ],
                    );
                  },
                ),
    );
  }
}