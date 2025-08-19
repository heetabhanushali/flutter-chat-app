import 'package:chat_app/screens/personal_chat.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _messageController.dispose();
    _recipientController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    try {
      setState(() => _isSearching = true);

      final response = await _supabase
          .from('users')
          .select('id, email, username, avatar_url')
          .or('email.ilike.%$query%,username.ilike.%$query%')
          .neq('id', _supabase.auth.currentUser?.id ?? '')
          .limit(10);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(response);
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching users: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildContactTile(Map<String, dynamic> user) {
    final String name = user['username'] ?? 'Unknown';
    final String email = user['email'] ?? '';
    final String? avatarUrl = user['avatar_url'];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
        child: avatarUrl == null 
            ? Icon(Icons.person, color: const Color.fromRGBO(255, 109, 77, 1.0))
            : null,
      ),
      title: Text(
        name , 
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 20),
      ),
      subtitle: Text(
        email,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[500]),
      ),
      onTap: () {
        _openPersonalChat(user);
      },
    );
  }

  void _openPersonalChat(Map<String, dynamic> user) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(
      builder:(context) => PersonalChatScreen(
        recipientUser: user , 
        onConversationCreated: (){
          chatListKey.currentState?.loadConversations();
        },
      ),));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [

          //------------------------------------------------------------
          // HEADER
          //------------------------------------------------------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: const Color.fromRGBO(255, 109, 77, 1.0), fontSize: 16),
                  ),
                ),
                const Spacer(),
                Text(
                  'New Message',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 20)
                ),
                const Spacer(),
                SizedBox(width: 60,),
              ],
            ),
          ),
          
          //------------------------------------------------------------
          // SEARCH FEATURE
          //------------------------------------------------------------
          Container(
            padding: const EdgeInsets.only(right: 16, left: 16 , top:5 ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey, width: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'To: ',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                  ),
                ),
                Expanded(
                  child: TextField(
                    autofocus: true,
                    cursorColor: const Color.fromRGBO(255, 109, 77, 1.0),
                    cursorHeight: 20,
                    controller: _recipientController,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search users...',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    onChanged: (value) {
                      _searchUsers(value);
                    },
                  ),
                ),
              ],
            ),
          ),

          //------------------------------------------------------------
          // SEARCH RESULTS OR EMPTY STATE
          //------------------------------------------------------------
          Expanded(
            child: _recipientController.text.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Start typing to search for users',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : _isSearching
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color.fromRGBO(255, 109, 77, 1.0),
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_search,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No users found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              return _buildContactTile(_searchResults[index]);
                            },
                          ),
          ),

        ],
      ),
    );
  }
}