import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ═══════════════════════════════════════════════════════════
  // PROFILE IMAGE
  // ═══════════════════════════════════════════════════════════

  // ─── Load Profile Image ───────────────────────────────────

  Future<String?> loadProfileImage() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    String? imageUrl = user.userMetadata?['avatar_url'] as String?;

    if (imageUrl == null) {
      final response = await _supabase
          .from('users')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      imageUrl = response?['avatar_url'] as String?;
    }

    return imageUrl;
  }

  // ─── Upload Profile Image ────────────────────────────────

  Future<String?> uploadProfileImage(File image) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final fileName = 'profile_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _supabase.storage
        .from('profile-images')
        .upload(fileName, image);

    return _supabase.storage.from('profile-images').getPublicUrl(fileName);
  }

  // ─── Update Profile with Avatar URL ──────────────────────

  Future<void> updateProfileAvatar(String? imageUrl) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase.auth.updateUser(
      UserAttributes(
        data: {'avatar_url': imageUrl},
      ),
    );

    try {
      await _supabase.from('users').upsert({
        'id': user.id,
        'avatar_url': imageUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Users table update failed (auth metadata updated): $e');
    }
  }

  // ─── Delete Profile Image from Storage ───────────────────

  Future<void> deleteProfileImageFromStorage(String imageUrl) async {
    final fileName = _extractFileName(imageUrl, 'profile-images');

    if (fileName != null && fileName.isNotEmpty) {
      await _supabase.storage
          .from('profile-images')
          .remove([fileName]);
    }
  }

  // ─── Full Delete Profile Image ───────────────────────────

  Future<void> deleteProfileImage(String imageUrl) async {
    try {
      await deleteProfileImageFromStorage(imageUrl);
    } catch (e) {
      print('Error deleting from storage: $e');
      // Continue even if storage deletion fails
    }
    await updateProfileAvatar(null);
  }

  // ═══════════════════════════════════════════════════════════
  // USER POST PHOTOS
  // ═══════════════════════════════════════════════════════════

  // ─── Load User Photos ────────────────────────────────────

  Future<List<Map<String, dynamic>>> loadUserPhotos(String userId) async {
    final response = await _supabase
        .from('user_photos')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // ─── Upload User Post Photo ──────────────────────────────

  Future<Map<String, dynamic>> uploadUserPhoto(File image) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final filePath = '${user.id}/$fileName';

    await _supabase.storage
        .from('user-photos')
        .upload(filePath, image);

    final imageUrl = _supabase.storage
        .from('user-photos')
        .getPublicUrl(filePath);

    final record = {
      'user_id': user.id,
      'photo_url': imageUrl,
      'file_path': filePath,
      'created_at': DateTime.now().toIso8601String(),
    };

    await _supabase.from('user_photos').insert(record);

    return record;
  }

  // ─── Delete User Post Photo ──────────────────────────────

  Future<void> deleteUserPhoto(Map<String, dynamic> photo) async {
    await _supabase.storage
        .from('user-photos')
        .remove([photo['file_path']]);

    await _supabase
        .from('user_photos')
        .delete()
        .eq('id', photo['id']);
  }

  // ═══════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════

  String? _extractFileName(String imageUrl, String bucketName) {
    try {
      final uri = Uri.parse(imageUrl);

      final pathSegments = uri.pathSegments;
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == bucketName && i + 1 < pathSegments.length) {
          return pathSegments[i + 1];
        }
      }

      final path = uri.path;
      final bucketIndex = path.indexOf('/$bucketName/');
      if (bucketIndex != -1) {
        return path.substring(bucketIndex + '/$bucketName/'.length);
      }

      final parts = imageUrl.split('/');
      if (parts.isNotEmpty) {
        return parts.last;
      }

      return null;
    } catch (e) {
      print('Error extracting filename: $e');
      return null;
    }
  }
}