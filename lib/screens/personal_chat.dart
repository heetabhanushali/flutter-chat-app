import 'package:chat_app/screens/info.dart';
import 'package:chat_app/widgets/chat_list.dart';
import 'package:chat_app/widgets/personal_chat_messages.dart';
import 'package:flutter/material.dart';
import 'package:chat_app/services/chat_service.dart';
import 'package:chat_app/services/realtime_service.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

class _PersonalChatScreenState extends State<PersonalChatScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final GlobalKey _messagesKey = GlobalKey();
  final ChatService _chatService = ChatService();
  final RealtimeService _realtimeService = RealtimeService();
  RealtimeChannel? _typingChannel;
  Timer? _typingDebounce;
  bool _isRecipientTyping = false;
  Timer? _typingTimeout;
  late AnimationController _typingAnimController;
  String? _conversationId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _typingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    
    _loadExistingConversation().then((_) {
      setState(() {});
      _setupTypingSubscription();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _typingAnimController.dispose(); 
    _realtimeService.unsubscribe(_typingChannel);
    _typingDebounce?.cancel();
    _typingTimeout?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _conversationId != null) {
      _chatService.markAllMessagesAsRead(_conversationId!);
    }
  }

  Future<void> _getOrCreateConversation() async {
    if (_chatService.currentUserId == null) return;

    final recipientId = widget.recipientUser['id'];

    try {
      _conversationId = await _chatService.getOrCreateConversation(recipientId);
      widget.onConversationCreated?.call();
      _setupTypingSubscription();  // ← ADD THIS
    } catch (e) {
      print('Error creating conversation: $e');
    }
  }

  Future<void> _loadExistingConversation() async {
    if (_chatService.currentUserId == null) return;

    final recipientId = widget.recipientUser['id'];

    try {
      _conversationId = await _chatService.getExistingConversation(
        recipientId, 
        markAsRead: true,
      );
    } catch (e) {
      print('Error loading conversation: $e');
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;
    if (_chatService.currentUserId == null) return;

    // Clear input immediately
    _messageController.clear();

    // If no conversation exists, create one first (this blocks, but only once)
    if (_conversationId == null) {
      if (mounted) setState(() { _isSending = true; });
      await _getOrCreateConversation();
      if (mounted) setState(() { _isSending = false; });
      if (_conversationId == null) return;
      (_messagesKey.currentState as dynamic)?.setConversationId(_conversationId);
    }

    // Generate unique IDs for this message
    final clientMessageId = const Uuid().v4();
    final tempId = 'temp_$clientMessageId';

    final tempMessage = {
      'id': tempId,
      'conversation_id': _conversationId,
      'sender_id': _chatService.currentUserId,
      'content': messageText,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'client_message_id': clientMessageId,
      'status': 'pending',
      'sender': {
        'username': 'You',
        'avatar_url': supabase.auth.currentUser?.userMetadata?['avatar_url'],
      },
    };

    // Show in UI immediately
    (_messagesKey.currentState as dynamic)?.addOptimisticMessage(tempMessage);

    // Save locally + queue for sending — returns instantly
    await _chatService.sendMessage(
      conversationId: _conversationId!,
      content: messageText,
      clientMessageId: clientMessageId,
    );

    // Refresh conversation list
    chatListKey.currentState?.loadConversations();
  }

  void _setupTypingSubscription() {
    if (_conversationId == null) return;

    _realtimeService.unsubscribe(_typingChannel);

    _typingChannel = _realtimeService.subscribeToTyping(
      conversationId: _conversationId!,
      onUserTyping: (userId) {
        if (userId == widget.recipientUser['id'] && mounted) {
          setState(() {
            _isRecipientTyping = true;
          });

          // Reset the timeout
          _typingTimeout?.cancel();
          _typingTimeout = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _isRecipientTyping = false;
              });
            }
          });
        }
      },
    );
  }

  void _onTyping() {
    if (_conversationId == null) return;

    if (_typingDebounce?.isActive ?? false) return;

    _realtimeService.broadcastTyping(conversationId: _conversationId!);

    _typingDebounce = Timer(const Duration(seconds: 2), () {});
  }

  Widget _buildTypingDots() {
    return SizedBox(
      width: 32,
      height: 20,
      child: AnimatedBuilder(
        animation: _typingAnimController,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final delay = index * 0.25;
              final value = ((_typingAnimController.value + delay) % 1.0);
              final bounce = value < 0.5
                  ? (value * 2)
                  : (2 - value * 2);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Transform.translate(
                  offset: Offset(0, -4 * bounce),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.grey[500]!.withOpacity(0.4 + 0.6 * bounce),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
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

          if (_isRecipientTyping)
          Container(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDots(),
                const SizedBox(width: 8),
                Text(
                  '${widget.recipientUser['username'] ?? 'User'} is typing',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
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
                          if (mounted) setState(() {});
                          _onTyping();
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