import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Getters ───────────────────────────────────────────────

  User? get currentUser => _supabase.auth.currentUser;
  String? get currentUserId => _supabase.auth.currentUser?.id;
  Session? get currentSession => _supabase.auth.currentSession;
  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;

  // ─── Login ─────────────────────────────────────────────────

  /// Returns email for a given username, or null if not found
  Future<String?> getEmailByUsername(String username) async {
    final result = await _supabase
        .from('users')
        .select('email')
        .ilike('username', username.trim())
        .maybeSingle();

    if (result == null ||
        result['email'] == null ||
        result['email'].toString().isEmpty) {
      return null;
    }

    return result['email'].toString().trim();
  }

  /// Sign in with email + password. Throws AuthException on failure.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.session == null) {
      throw AuthException('Login failed');
    }

    return response;
  }

  // ─── Registration ──────────────────────────────────────────

  /// Returns true if the username is already taken
  Future<bool> isUsernameTaken(String username) async {
    final existing = await _supabase
        .from('users')
        .select('id')
        .eq('username', username)
        .maybeSingle();

    return existing != null;
  }

  /// Creates auth user. Throws AuthException on failure.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'username': username},
    );

    if (response.user == null) {
      throw AuthException('Registration failed');
    }

    return response;
  }

  /// Inserts/upserts user row into the `users` table
  Future<void> createUserProfile({
    required String userId,
    required String username,
    required String email,
  }) async {
    await _supabase.from('users').upsert({
      'id': userId,
      'username': username,
      'email': email.trim(),
    });
  }

  // ─── Password Reset ───────────────────────────────────────

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  // ─── Sign Out ──────────────────────────────────────────────

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // ─── Delete Account ───────────────────────────────────────

  Future<void> deleteAccount() async {
    // TODO: Implement full deletion (messages, photos, storage, auth user)
    throw UnimplementedError('Delete account functionality coming soon!');
  }
}