class ConversationWithUser {
  final String id;
  final UserProfile otherUser;
  final String lastMessage;
  final DateTime updatedAt;
  final bool isUnread;


  ConversationWithUser({
    required this.id,
    required this.otherUser,
    required this.lastMessage,
    required this.updatedAt,
    required this.isUnread
  });
}

class UserProfile {
  final String id;
  final String username;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      username: json['username'] ?? '',
      avatarUrl: json['avatar_url'],
    );
  }
}

