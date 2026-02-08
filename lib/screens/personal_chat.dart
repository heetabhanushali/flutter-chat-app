import 'package:chat_app/screens/info.dart';
import 'package:chat_app/widgets/chat_list.dart';
import 'package:chat_app/widgets/personal_chat_messages.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;
final GlobalKey<ChatListState> chatListKey = GlobalKey<ChatListState>();

class PersonalChatScreen extends StatefulWidget {
  final Map<String, dynamic> recipientUser;

  final VoidCallback? onConversationCreated;

  const PersonalChatScreen({
    super.key,
    required this.recipientUser,
    this.onConversationCreated,
  });

  @override
  State<PersonalChatScreen> createState() => _PersonalChatScreenState();
}

class _PersonalChatScreenState extends State<PersonalChatScreen> with WidgetsBindingObserver{
  final TextEditingController _messageController = TextEditingController();
  final GlobalKey _messagesKey = GlobalKey();
  
  String? _conversationId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadExistingConversation().then((_){
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Mark messages as read when user returns to the chat
      _markAllMessagesAsRead();
    }
  }

  Future<void> _GetOrCreateConversation() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    final recipientId = widget.recipientUser['id'];

    try {
      final existingConversation = await supabase
          .from('conversations')
          .select('id')
          .or(
            'and(participant1_id.eq.$currentUserId,participant2_id.eq.$recipientId),'
            'and(participant1_id.eq.$recipientId,participant2_id.eq.$currentUserId)'
          )
          .maybeSingle();

      if (existingConversation != null) {
        _conversationId = existingConversation['id'];
        return;
      }

      final newConversation = await supabase.from('conversations').insert({
        'participant1_id': currentUserId,
        'participant2_id': recipientId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select('id').single();

      _conversationId = newConversation['id'];
      widget.onConversationCreated?.call();
    } catch (e) {
      print('Error creating conversation: $e');
    }
  }

  Future<void> _loadExistingConversation() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    final recipientId = widget.recipientUser['id'];

    try {
      final existingConversation = await supabase
          .from('conversations')
          .select('id')
          .or(
            'and(participant1_id.eq.$currentUserId,participant2_id.eq.$recipientId),'
            'and(participant1_id.eq.$recipientId,participant2_id.eq.$currentUserId)'
          )
          .maybeSingle();

      if (existingConversation != null) {
        _conversationId = existingConversation['id'];
        // Mark all messages as read when opening the chat
        await _markAllMessagesAsRead();
      }
    } catch (e) {
      print('Error loading conversation: $e');
    }
  }

  Future<void> _markAllMessagesAsRead() async {
    if (_conversationId == null) return;
    
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Get all unread messages in this conversation that were sent by the other user
      final unreadMessages = await supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', _conversationId!)
          .neq('sender_id', currentUserId);

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
      print('Error marking messages as read: $e');
    }
  }


  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _isSending) return;

    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    // If conversation doesn't exist yet, create it
    if (_conversationId == null) {
      await _GetOrCreateConversation();
      if (_conversationId == null) return; // failed to create conversation
    }

    _messageController.clear();
    setState(() {
      _isSending = true;
    });

    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'conversation_id': _conversationId,
      'sender_id': currentUserId,
      'content': messageText,
      'created_at': DateTime.now().toIso8601String(),
      'sender': {
        'username': 'You',
        'avatar_url': supabase.auth.currentUser?.userMetadata?['avatar_url'],
      },
    };

    // Add optimistic message
    (_messagesKey.currentState as dynamic)?.addOptimisticMessage(tempMessage);

    try {
      await supabase.from('messages').insert({
        'conversation_id': _conversationId,
        'sender_id': currentUserId,
        'content': messageText,
        'created_at': DateTime.now().toIso8601String(),
      });

      await supabase.from('conversations').update({
        'last_message': messageText,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _conversationId!);

    } catch (e) {
      (_messagesKey.currentState as dynamic)?.removeOptimisticMessage(tempMessage['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _messageController.text = messageText;
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final recipientName = widget.recipientUser['username'] ?? 'Unknown User';
    final recipientAvatarUrl = widget.recipientUser['avatar_url'];

    return Scaffold(

      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: ()async {
            // chatListKey.currentState?.loadConversations();
            Navigator.pop(context , true);
          } 
        ),
        title: GestureDetector(
          onTap: (){
            Navigator.of(context).push(MaterialPageRoute(builder:(context) => InfoPage(recipientUser: widget.recipientUser),));
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                backgroundImage: recipientAvatarUrl != null 
                    ? NetworkImage(recipientAvatarUrl) 
                    : null,
                child: recipientAvatarUrl == null 
                    ? Icon(Icons.person, color: const Color.fromRGBO(255, 109, 77, 1.0), size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  recipientName,
                  style: Theme.of(context).textTheme.bodyLarge
                ),
              ),
            ],
          ),
        ),
      ),


      body: Column(
        children: [

          PersonalChatMessages(
            key: _messagesKey,
            conversationId: _conversationId,
            recipientUser: widget.recipientUser,
          ),

          
          
          //---------------------------------------------------------------------------
          // MESSAGE INPUT AREA
          //---------------------------------------------------------------------------
          Container(
            padding: const EdgeInsets.all(12),
            child: SafeArea(
              child: Row(
                children: [

                  //---------------------------------------------------------------------------
                  // MESSAGE TYPE AREA
                  //---------------------------------------------------------------------------
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5E5EA)),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        onChanged:(text) {
                          setState(() {
                          });
                        },
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  //---------------------------------------------------------------------------
                  // SEND BUTTON
                  //---------------------------------------------------------------------------
                  GestureDetector(
                    onTap: (_messageController.text.trim().isNotEmpty && !_isSending) 
                        ? _sendMessage 
                        : null,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (_messageController.text.trim().isNotEmpty && !_isSending) 
                            ? const Color.fromRGBO(255, 109, 77, 1.0)
                            : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              Icons.arrow_upward,
                              color: (_messageController.text.trim().isNotEmpty && !_isSending) 
                                  ? Colors.white 
                                  : Colors.grey[600],
                              size: 18,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}