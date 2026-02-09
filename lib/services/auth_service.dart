import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/services/encryption_service.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final EncryptionService _encryptionService = EncryptionService();

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
        .select('email, username')
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

  // ─── Delete Account ───────────────────────────────────────

  Future<void> deleteAccount() async {
    // TODO: Implement full deletion (messages, photos, storage, auth user)
    throw UnimplementedError('Delete account functionality coming soon!');
  }

  // ─── E2EE Key Setup ───────────────────────────────────────

  /// Called after registration — generates fresh keys
  Future<void> setupEncryptionKeys({
    required String userId,
    required String password,
  }) async {
    await _encryptionService.generateAndStoreKeys(
      userId: userId,
      password: password,
    );
  }

  /// Called after login — recovers keys to this device
  Future<void> recoverEncryptionKeys({
    required String userId,
    required String password,
  }) async {
    try{
      final hasLocal = await _encryptionService.hasLocalKeys();
      if (hasLocal) return; 

      final hasServer = await _encryptionService.hasServerKeys(userId);
      if (!hasServer){
        print("Upgrading old user to E2EE...");
        await _encryptionService.generateAndStoreKeys(
          userId: userId,
          password: password,
        );
        return;
      } 

      final success = await _encryptionService.recoverKeysFromServer(
        userId: userId,
        password: password,
      );

      if (!success) {
        print('Warning: Could not recover encryption keys');
      }
    } catch (e) {
      print('E2EE setup skipped: $e');
    }
  } 

  // ─── Modify existing signOut ──────────────────────────────

  Future<void> signOut() async {
    await _encryptionService.clearLocalKeys();
    await _supabase.auth.signOut();
  }

}