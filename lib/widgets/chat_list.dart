import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/screens/personal_chat.dart';
import 'package:chat_app/widgets/conversation_tile.dart';
import 'package:chat_app/models/models.dart';
import 'package:chat_app/services/chat_service.dart';
import 'package:chat_app/services/realtime_service.dart';
import 'package:chat_app/services/connectivity_service.dart';
import 'package:chat_app/services/message_queue_service.dart';


class ChatList extends StatefulWidget {
  const ChatList({super.key});

  @override
  State<ChatList> createState() => ChatListState();
}

class ChatListState extends State<ChatList> with WidgetsBindingObserver {
  final SupabaseClient supabase = Supabase.instance.client;
  List<ConversationWithUser> conversations = [];
  bool isLoading = true;
  String? error;
  RealtimeChannel? _conversationsSubscription;
  final ChatService _chatService = ChatService();
  final RealtimeService _realtimeService = RealtimeService();
  final ConnectivityService _connectivity = ConnectivityService();
  final MessageQueueService _messageQueue = MessageQueueService();
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<MessageStatusEvent>? _queueSub;
  final Map<String, bool> _typingUsers = {};
  final Map<String, Timer> _typingTimers = {};
  final Map<String, RealtimeChannel> _typingChannels = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConversations();

    _connectivitySub = _connectivity.onConnectivityChanged.listen((online) {
      if (online && mounted) {
        loadConversations();
      }
    });
    _queueSub = _messageQueue.statusUpdates.listen((event) {
      if (event.status == 'sent' && mounted) {
        loadConversations();
      }
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conversationsSubscription?.unsubscribe();
    _cleanupTypingSubscriptions();
    _connectivitySub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }

  void _initConversations() async{
    await loadConversations();
    _setupRealtimeSubscription();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) loadConversations();
  }

  Future<void> loadConversations() async {
    try {
      if (_chatService.currentUserId == null) return;

      final conversationsData = await _chatService.loadConversations();

      if (!mounted) return;

      final newConversations = conversationsData.map((conv) {
        final rawTime = conv['updatedAt']?.toString() ?? '';
        final updatedAt = rawTime.endsWith('Z') || rawTime.contains('+')
            ? DateTime.parse(rawTime)
            : DateTime.parse(rawTime + 'Z');

        return ConversationWithUser(
          id: conv['id'],
          otherUser: UserProfile.fromJson(conv['otherUser']),
          lastMessage: conv['lastMessage'],
          updatedAt: updatedAt,
          isUnread: conv['isUnread'],
        );
      }).toList();

      setState(() {
        conversations = newConversations;
        isLoading = false;
        error = null;
      });

      _setupTypingSubscriptions();
    } catch (e) {
      print('Error loading conversations: $e');
      if (mounted) {
        setState(() {
          // error = e.toString();
          isLoading = false;
          error = null;
        });
      }
    }
  }

  void _setupTypingSubscriptions() {
    _cleanupTypingSubscriptions();

    for (final conv in conversations) {
      final conversationId = conv.id;
      final otherUserId = conv.otherUser.id;

      final channel = supabase
          .channel('typing_$conversationId')
          .onBroadcast(
            event: 'typing',
            callback: (payload) {
              final typingUserId = payload['user_id'] as String?;
              if (typingUserId != null && typingUserId == otherUserId && mounted) {
                setState(() {
                  _typingUsers[otherUserId] = true;
                });

                _typingTimers[otherUserId]?.cancel();
                _typingTimers[otherUserId] = Timer(
                  const Duration(seconds: 3),
                  () {
                    if (mounted) {
                      setState(() {
                        _typingUsers[otherUserId] = false;
                      });
                    }
                  },
                );
              }
            },
          )
          .subscribe();

      _typingChannels[conversationId] = channel;
    }
  }

  void _cleanupTypingSubscriptions() {
    for (final channel in _typingChannels.values) {
      channel.unsubscribe();
    }
    _typingChannels.clear();

    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingUsers.clear();
  }

  void _setupRealtimeSubscription() {
    if (_chatService.currentUserId == null) return;

    _conversationsSubscription = _realtimeService.subscribeToConversationList(
      onConversationChange: () {
        loadConversations();
      },
      onConversationDeleted: (conversationId) {
        if (mounted) {
          setState(() {
            conversations.removeWhere((c) => c.id == conversationId);
          });
        }
      },
      onNewMessage: (messageData) async {
        loadConversations();
      },
      onReadStatusChange: () {
        loadConversations();
      },
    );
  }

  Future<void> _refreshConversations() async {
    await loadConversations();
  }

  Future<void> _deleteConversationForUser(String conversationId) async {
    try {
      await _chatService.deleteConversationForUser(conversationId);

      if (mounted) {
        setState(() {
          conversations.removeWhere((c) => c.id == conversationId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conversation deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error: $e');
      print('Stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting conversation: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        loadConversations();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading conversations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshConversations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'No conversations yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation with someone!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshConversations,
      child: ListView.builder(
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          final isTyping = _typingUsers[conversation.otherUser.id] ?? false;
          return Dismissible(
            key: Key('conversation_${conversation.id}_${conversation.hashCode}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: Theme.of(context).colorScheme.error,
              child: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.onError,
                size: 28,
              ),
            ),
            confirmDismiss: (direction) async {

              if (!mounted) {
                return false;
              }

              try {
                final result = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext dialogContext) {
                    return AlertDialog(
                      title: const Text('Delete Conversation'),
                      content: Text(
                        'Are you sure you want to delete this conversation with ${conversation.otherUser.username}? This will only delete it for you.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop(false);
                          },
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop(true);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    );
                  },
                );
                return result == true;
              } catch (e) {
                print('ERROR in confirmDismiss: $e');
                print('Stack trace: ${StackTrace.current}');
                return false;
              }
            },
            onDismissed: (direction) {
              _deleteConversationForUser(conversation.id);
            },
            child: ConversationTile(
              conversation: conversation,
              isTyping: isTyping,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PersonalChatScreen(
                      recipientUser: {
                        'id': conversation.otherUser.id,
                        'username': conversation.otherUser.username,
                        'avatar_url': conversation.otherUser.avatarUrl,
                      },
                    ),
                  ),
                );
                if (mounted) loadConversations();
              },
              onDelete: () {},
            ),
          );
        },
      ),
    );
  }
}