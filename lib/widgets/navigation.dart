import 'package:chat_app/screens/chat.dart';
import 'package:chat_app/screens/chat_bot.dart';
import 'package:chat_app/screens/user.dart';
import 'package:flutter/material.dart';

class Navigation extends StatefulWidget {
  const Navigation({super.key});

  @override
  State<Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<Navigation> {
  int _currentIndex = 1;
  List<Widget> body = const [
    ChatBotPage(),
    ChatScreen(),
    UserPage()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: body[_currentIndex],

      bottomNavigationBar: BottomNavigationBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.background,
        selectedItemColor: const Color.fromRGBO(255, 109, 77, 1.0),
        unselectedItemColor: const Color.fromRGBO(255, 109, 77, 1.0),
        currentIndex: _currentIndex,
        onTap: (int new_index){
          setState(() {
            _currentIndex = new_index;
          });
        },

        items: [
          BottomNavigationBarItem(
            label: 'AI',
            icon: Icon(_currentIndex == 0? Icons.circle : Icons.circle_outlined)
          ),
          BottomNavigationBarItem(
            label: 'Chat',
            icon: Icon(_currentIndex == 1 ? Icons.chat_bubble : Icons.chat_bubble_outline),
          ),
          BottomNavigationBarItem(
            label: 'User',
            icon: Icon(_currentIndex == 2? Icons.person : Icons.person_outline),
          ),
        ],
      ),
    );
  }
}