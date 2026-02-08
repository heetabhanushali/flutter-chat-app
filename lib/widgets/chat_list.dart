import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/screens/personal_chat.dart';
import 'package:chat_app/widgets/conversation_tile.dart';
import 'package:chat_app/models/models.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConversations();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conversationsSubscription?.unsubscribe();
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
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get all deleted conversations for current user
      final deletedConversationsResponse = await supabase
        .from('user_deleted_conversations')
        .select('conversation_id, deleted_at')
        .eq('user_id', currentUserId);

      final Map<String, DateTime> deletedConversations = {};
      for (final deleted in deletedConversationsResponse) {
        deletedConversations[deleted['conversation_id']] = 
          DateTime.parse(deleted['deleted_at']).toUtc();
      }

      // Get all conversations where user is a participant
      final response = await supabase
          .from('conversations')
          .select('''
            *,
            participant1:users!participant1_id(id, username, avatar_url),
            participant2:users!participant2_id(id, username, avatar_url)
          ''')
          .or('participant1_id.eq.$currentUserId,participant2_id.eq.$currentUserId')
          .order('updated_at', ascending: false);

      if (!mounted) return;

      final newConversations = <ConversationWithUser>[];

      for (final conv in response) {
        final conversationId = conv['id'];
        
        if (deletedConversations.containsKey(conversationId)) {
          final deletedAtUtc = deletedConversations[conversationId]!;
          
          // Check if there are any messages after the deletion time
          final messagesAfterDeletion = await supabase
              .from('messages')
              .select('id, created_at')
              .eq('conversation_id', conversationId)
              .order('created_at', ascending: false)
              .limit(5);
          
          // Filter messages that are after deletion time
          final validMessages = messagesAfterDeletion.where((msg) {
            final msgTime = DateTime.parse(msg['created_at'] + 'Z').toUtc();
            return msgTime.isAfter(deletedAtUtc);
          }).toList();
          
          // Only include if there are messages after deletion
          if (validMessages.isNotEmpty) {
            final isParticipant1 = conv['participant1_id'] == currentUserId;
            final otherUser = isParticipant1 ? conv['participant2'] : conv['participant1'];
            
            final isUnread = await _isConversationUnread(conv['id'], currentUserId);

            newConversations.add(ConversationWithUser(
              id: conv['id'],
              otherUser: UserProfile.fromJson(otherUser),
              lastMessage: conv['last_message'] ?? '',
              updatedAt: DateTime.parse(conv['updated_at']),
              isUnread: isUnread,
            ));
          } 
        } else {
          // Conversation not deleted, include it
          final isParticipant1 = conv['participant1_id'] == currentUserId;
          final otherUser = isParticipant1 ? conv['participant2'] : conv['participant1'];
          
          final isUnread = await _isConversationUnread(conv['id'], currentUserId);

          newConversations.add(ConversationWithUser(
            id: conv['id'],
            otherUser: UserProfile.fromJson(otherUser),
            lastMessage: conv['last_message'] ?? '',
            updatedAt: DateTime.parse(conv['updated_at']),
            isUnread: isUnread,
          ));
        }
      }

      setState(() {
        conversations = newConversations;
        isLoading = false;
        error = null;
      });

    } catch (e) {
      print('Error loading conversations: $e');
      if (mounted) {
        setState(() {
          error = e.toString();
          isLoading = false;
        });
      }
    }
  }

  void _setupRealtimeSubscription() {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    _conversationsSubscription = supabase
        .channel('chat_updates_$currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) {
            loadConversations();
          }
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert, 
          schema: 'public',
          table: 'user_deleted_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUserId,
          ),
          callback: (payload) {
            final deletedConversationId = payload.newRecord['conversation_id'];
            if (deletedConversationId != null) {
              setState(() {
                conversations.removeWhere((c) => c.id == deletedConversationId);
              });
            }
          }
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final newRecord = payload.newRecord;
            final conversationId = newRecord['conversation_id'];
            final senderId = newRecord['sender_id'];
            if (conversationId == null) return;

            // Check if this conversation involves the current user
            final conversationCheck = await supabase
                .from('conversations')
                .select('id, participant1_id, participant2_id')
                .eq('id', conversationId)
                .maybeSingle();
                
            if (conversationCheck == null) return;

            final p1 = conversationCheck['participant1_id'];
            final p2 = conversationCheck['participant2_id'];
            if (p1 != currentUserId && p2 != currentUserId) return;

            // Check if conversation was previously deleted by user
            final deletionResponse = await supabase
                .from('user_deleted_conversations')
                .select('deleted_at')
                .eq('user_id', currentUserId)
                .eq('conversation_id', conversationId)
                .maybeSingle();

            bool shouldShowConversation = true;
            
            if (deletionResponse != null) {
              final deletedAtUtc = DateTime.parse(deletionResponse['deleted_at']).toUtc();
              final messageTimeUtc = DateTime.parse(newRecord['created_at']).toUtc();
              
              // Only show if message is after deletion time
              shouldShowConversation = messageTimeUtc.isAfter(deletedAtUtc);
            }

            if (!shouldShowConversation) return;

            // Check if conversation already exists in list
            final existingIndex = conversations.indexWhere((c) => c.id == conversationId);
            
            if (existingIndex == -1) {
              // Add new conversation to the list
              final newConv = await supabase
                  .from('conversations')
                  .select('''
                    id,
                    participant1_id,
                    participant2_id,
                    last_message,
                    updated_at,
                    participant1:participant1_id(id, username, avatar_url),
                    participant2:participant2_id(id, username, avatar_url)
                  ''')
                  .eq('id', conversationId)
                  .maybeSingle();
              
              if (newConv != null) {
                final otherUser = (newConv['participant1_id'] == currentUserId)
                    ? newConv['participant2']
                    : newConv['participant1'];

                
                if (otherUser != null && mounted) {
                  final isUnread = senderId != currentUserId;
                  setState(() {
                    conversations.insert(
                      0,
                      ConversationWithUser(
                        id: newConv['id'], 
                        otherUser: UserProfile.fromJson(otherUser), 
                        lastMessage: newConv['last_message'] ?? '', 
                        updatedAt: DateTime.parse(newConv['updated_at']),
                        isUnread: isUnread,
                      )
                    );
                  });
                }
              }
            } else {
              // Update existing conversation (move to top and update last message)
              loadConversations();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public', 
          table: 'message_read_status',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, 
            column: 'user_id', 
            value: currentUserId,
          ),
          callback: (payload){
            loadConversations();
          }
        )
        .subscribe();
  }

  Future<bool> _isConversationUnread(String conversationId, String currentUserId) async {
    try {
      // Get the latest message in this conversation
      final latestMessage = await supabase
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
      final readStatus = await supabase
          .from('message_read_status')
          .select('id')
          .eq('message_id', latestMessage['id'])
          .eq('user_id', currentUserId)
          .maybeSingle();

      // If no read status exists, the message is unread
      return readStatus == null;
    } catch (e) {
      print('Error checking read status: $e');
      return false;
    }
  }

  Future<void> _refreshConversations() async {
    await loadConversations();
  }

  Future<void> _deleteConversationForUser(String conversationId) async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null){
        return;
      }

      await supabase
          .from('user_deleted_conversations')
          .delete()
          .eq('user_id', currentUserId)
          .eq('conversation_id', conversationId);

      final deletionTime = DateTime.now().toUtc().toIso8601String();

      await supabase
          .from('user_deleted_conversations')
          .insert({
            'user_id': currentUserId,
            'conversation_id': conversationId,
            'deleted_at': deletionTime,
          });

      // Show confirmation
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
            ),
          );
        },
      ),
    );
  }
}