import 'package:chat_app/screens/chat.dart';
import 'package:chat_app/screens/chat_bot.dart';
import 'package:chat_app/screens/user.dart';
import 'package:chat_app/services/connectivity_service.dart';
import 'package:chat_app/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';

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

  final ConnectivityService _connectivity = ConnectivityService();
  final ChatService _chatService = ChatService();
  StreamSubscription<bool>? _connectivitySub;
  bool _isOffline = false;
  bool _showBanner = false;
  Timer? _bannerDelay;

  @override
  void initState() {
    super.initState();
    _connectivity.startMonitoring();
    _chatService.initQueue();

    _connectivitySub = _connectivity.onConnectivityChanged.listen((online) {
      _isOffline = !online;

      if (!online) {
        _bannerDelay?.cancel();
        _bannerDelay = Timer(const Duration(seconds: 2), () {
          if (_isOffline && mounted) {
            setState(() {
              _showBanner = true;
            });
          }
        });
      } else {
        _bannerDelay?.cancel();
        if (mounted) {
          // Only show "Connected" if we were showing the offline banner
          if (_showBanner) {
            setState(() {
              _showBanner = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.wifi, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Connected'),
                  ],
                ),
                backgroundColor: Colors.green[600],
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(bottom: 20, left: 20, right: 20),
              ),
            );
          } else {
            setState(() {
              _showBanner = false;
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _bannerDelay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main content — full screen, unchanged
          body[_currentIndex],

          // Offline banner — floats on top
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            top: _showBanner ? 0 : -(MediaQuery.of(context).padding.top + 28),
            left: 0,
            right: 0,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                bottom: 6,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Waiting for network',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: BottomNavigationBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.background,
        selectedItemColor: const Color.fromRGBO(255, 109, 77, 1.0),
        unselectedItemColor: const Color.fromRGBO(255, 109, 77, 1.0),
        currentIndex: _currentIndex,
        onTap: (int new_index) {
          setState(() {
            _currentIndex = new_index;
          });
        },
        items: [
          BottomNavigationBarItem(
            label: 'AI',
            icon: Icon(_currentIndex == 0 ? Icons.circle : Icons.circle_outlined)
          ),
          BottomNavigationBarItem(
            label: 'Chat',
            icon: Icon(_currentIndex == 1 ? Icons.chat_bubble : Icons.chat_bubble_outline),
          ),
          BottomNavigationBarItem(
            label: 'User',
            icon: Icon(_currentIndex == 2 ? Icons.person : Icons.person_outline),
          ),
        ],
      ),
    );
  }
}