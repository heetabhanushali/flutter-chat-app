import 'package:supabase_flutter/supabase_flutter.dart';

class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Get User Info (for messages) ───────────────────────────
  Future<Map<String, dynamic>> getUserInfo(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('username, avatar_url')
          .eq('id', userId)
          .single();

      return response;
    } catch (e) {
      print('Error fetching user info: $e');
      return {'username': 'Unknown', 'avatar_url': null};
    }
  }

  // ─── Get User Data by ID ──────────────────────────────────

  /// Returns user row from the `users` table for a given user ID
  Future<Map<String, dynamic>> getUserById(String userId) async {
    final response = await _supabase
        .from('users')
        .select('username, email, avatar_url')
        .eq('id', userId)
        .single();

    return response;
  }

  // ─── Get Current User Data ────────────────────────────────

  /// Returns current user's data from the `users` table.
  /// Falls back to auth metadata if table query fails.
  Future<Map<String, dynamic>> getCurrentUserData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      return await getUserById(user.id);
    } catch (e) {
      // Fallback to auth user data
      return {
        'username': user.email?.split('@')[0] ?? 'Unknown User',
        'email': user.email ?? 'No email',
        'avatar_url': null,
      };
    }
  }

  // ─── Search Users ─────────────────────────────────────────

  /// Searches users by username or email, excluding the current user.
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    final currentUserId = _supabase.auth.currentUser?.id ?? '';

    final response = await _supabase
        .from('users')
        .select('id, email, username, avatar_url')
        .or('email.ilike.%$query%,username.ilike.%$query%')
        .neq('id', currentUserId)
        .limit(10);

    return List<Map<String, dynamic>>.from(response);
  }
}