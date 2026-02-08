import 'package:chat_app/widgets/chat_list.dart';
import 'package:chat_app/widgets/new_message_screen.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        toolbarHeight: 75,
        title: Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Text(
            'Messages',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 40 , fontWeight: FontWeight.bold),
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: CircleAvatar(
              backgroundColor: const Color.fromRGBO(255, 109, 77, 1.0), // Circle background color
              radius: 18, // Circle size
              child: IconButton(
                onPressed: () async {
                  await showModalBottomSheet<Map<String, dynamic>>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const NewMessageScreen(),
                  );
                },
                icon: const Icon(Icons.add, size: 20, color: Colors.white,), // Icon color
              ),
            ),
            
          ),
        ],
      ),
      body: ChatList(),
    );
  }
}