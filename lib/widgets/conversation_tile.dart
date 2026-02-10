import 'package:flutter/material.dart';
import 'package:chat_app/models/models.dart';
import 'package:chat_app/services/chat_service.dart';

class ConversationTile extends StatefulWidget {
  final ConversationWithUser conversation;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool isTyping;

  const ConversationTile({
    super.key,
    required this.conversation,
    this.onTap,
    this.onDelete,
    this.isTyping = false,
  });

  @override
  State<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile> with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  late AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now(); 
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _markConversationAsRead() async {
    if (!widget.conversation.isUnread) return;
    try {
      await _chatService.markConversationAsRead(widget.conversation.id);
    } catch (e) {
      print('Error marking conversation as read: $e');
    }
  }

  Future<void> _deleteConversationForUser() async {
    try {
      await _chatService.deleteConversationForUser(widget.conversation.id);      
      widget.onDelete?.call();
    } catch (e) {
      print('Error deleting conversation: $e');
    }
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Delete Conversation',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 25
            ),
          ),
          content: Text(
            'Are you sure you want to delete this conversation with ${widget.conversation.otherUser.username}? This action cannot be undone.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 20
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color.fromRGBO(255, 109, 77, 1.0),
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromRGBO(255, 109, 77, 1.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteConversationForUser();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTypingDots() {
    return SizedBox(
      width: 24,
      height: 16,
      child: _TypingDotsAnim(controller: _dotController),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(widget.conversation.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        _showDeleteConfirmation(context);
        return false;
      },
      background: Container(
        margin: EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.delete,
          color: Theme.of(context).colorScheme.onError,
          size: 24,
        ),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        elevation: 0,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            radius: 24,
            backgroundImage: widget.conversation.otherUser.avatarUrl != null
                ? NetworkImage(widget.conversation.otherUser.avatarUrl!)
                : null,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: widget.conversation.otherUser.avatarUrl == null
                ? Icon(Icons.person, color: const Color.fromRGBO(255, 109, 77, 1.0))
                : null,
          ),
          title: Text(
            widget.conversation.otherUser.username,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: widget.isTyping
                ? Row(
                    children: [
                      Text(
                        'typing',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color.fromRGBO(255, 109, 77, 1.0),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      SizedBox(width: 5,),
                      _buildTypingDots(),
                    ],
                  )
                : Text(
                    widget.conversation.lastMessage.isNotEmpty
                        ? widget.conversation.lastMessage
                        : 'No messages yet',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
          ),
          trailing: Column(
            children: [
              Text(
                _formatTimestamp(widget.conversation.updatedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: widget.conversation.isUnread 
                      ? const Color.fromRGBO(255, 109, 77, 1.0) 
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 12),
              if (widget.conversation.isUnread)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 109, 77, 1.0),
                    shape: BoxShape.circle
                  ),
                )
            ],
          ),
          onTap: () {
            _markConversationAsRead();
            widget.onTap?.call();
          },
        ),
      ),
    );
  }
}

class _TypingDotsAnim extends AnimatedWidget {
  const _TypingDotsAnim({required AnimationController controller})
      : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final controller = listenable as AnimationController;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final delay = index * 0.25;
        final value = ((controller.value + delay) % 1.0);
        final bounce = value < 0.5 ? (value * 2) : (2 - value * 2);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Transform.translate(
            offset: Offset(0, -3 * bounce),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 109, 77, 1.0).withOpacity(0.4 + 0.6 * bounce),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}