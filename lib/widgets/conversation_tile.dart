import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/models/models.dart';

class ConversationTile extends StatelessWidget {
  final ConversationWithUser conversation;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const ConversationTile({
    super.key,
    required this.conversation,
    this.onTap,
    this.onDelete,
  });

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
    if (!conversation.isUnread) return; // Already read, no need to update
    
    try {
      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser?.id;
      
      if (currentUserId == null) return;

      // Get the latest message in this conversation
      final latestMessage = await supabase
          .from('messages')
          .select('id, sender_id')
          .eq('conversation_id', conversation.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (latestMessage == null || latestMessage['sender_id'] == currentUserId) {
        return; // No message or user sent the latest message
      }

      // Check if already marked as read
      final existingRead = await supabase
          .from('message_read_status')
          .select('id')
          .eq('message_id', latestMessage['id'])
          .eq('user_id', currentUserId)
          .maybeSingle();

      // Only insert if not already marked as read
      if (existingRead == null) {
        await supabase
            .from('message_read_status')
            .insert({
              'message_id': latestMessage['id'],
              'user_id': currentUserId,
            });
      }
    } catch (e) {
      print('Error marking conversation as read: $e');
    }
  }

  Future<void> _deleteConversationForUser(BuildContext context) async {
    try {
      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser?.id;
      
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      await supabase.from('user_deleted_conversations').insert({
        'user_id': currentUserId,
        'conversation_id': conversation.id,
        'deleted_at': DateTime.now().toIso8601String(),
      });
      
      onDelete?.call();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversation deleted'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting conversation: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
            'Are you sure you want to delete this conversation with ${conversation.otherUser.username}? This action cannot be undone.',
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
                backgroundColor: const Color.fromRGBO(255, 109, 77, 1.0), // orange
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
                _deleteConversationForUser(context);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(conversation.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        _showDeleteConfirmation(context);
        return false; // Don't auto-dismiss, we handle it manually
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
            backgroundImage: conversation.otherUser.avatarUrl != null
                ? NetworkImage(conversation.otherUser.avatarUrl!)
                : null,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: conversation.otherUser.avatarUrl == null
                ? Icon(Icons.person, color: const Color.fromRGBO(255, 109, 77, 1.0))
                : null,
          ),
          title: Text(
            conversation.otherUser.username,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              conversation.lastMessage.isNotEmpty
                  ? conversation.lastMessage
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
                _formatTimestamp(conversation.updatedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: conversation.isUnread ? const Color.fromRGBO(255, 109, 77, 1.0) : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              SizedBox(height:12),
              if (conversation.isUnread)
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
          onTap: (){
            _markConversationAsRead();
            onTap?.call();
          },
        ),
      ),
    );
  }
}