import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chat_app/widgets/user_avatar.dart';

final supabase = Supabase.instance.client;

class UserImagePicker extends StatefulWidget {
  const UserImagePicker({super.key});

  @override
  State<UserImagePicker> createState() => _UserImagePickerState();
}

class _UserImagePickerState extends State<UserImagePicker> {
  File? _pickedImageFile;
  String? avatarUrl;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
  }

  Future<void> _showImageOptionsBottomSheet() async {
    showModalBottomSheet(
      backgroundColor: Theme.of(context).colorScheme.background,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with centered title and close button in circle
              Row(
                children: [
                  const SizedBox(width: 40), // Space to balance the close button
                  const Expanded(
                    child: Text(
                      'Edit Profile Photo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    height: 30,
                    width: 30,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(255, 109, 77, 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.only(right: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Take Photo and Choose Photo in one container with divider
              Container(
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 109, 77, 0.02),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color.fromRGBO(255, 109, 77, 0.2)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      trailing: const Icon(Icons.camera_alt, color: Colors.black),
                      title: const Text(
                        'Take Photo',
                        style: TextStyle(fontSize: 16),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _pickImageFromSource(ImageSource.camera);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.grey[300],
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      trailing: const Icon(Icons.photo_library, color: Colors.black),
                      title: const Text(
                        'Choose Photo',
                        style: TextStyle(fontSize: 16),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _pickImageFromSource(ImageSource.gallery);
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Delete Photo in separate red container (only show if image exists)
              if (avatarUrl != null)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 109, 77, 0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color.fromRGBO(255, 109, 77, 0.2)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    trailing: const Icon(Icons.delete, color: Colors.red),
                    title: const Text(
                      'Delete Photo',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _deleteProfileImage();
                    },
                  ),
                ),
              
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? pickedImage = await picker.pickImage(source: source);

    if (pickedImage != null) {
      setState(() {
        _pickedImageFile = File(pickedImage.path);
        isLoading = true;
      });

      // Delete old image before uploading new one
      if (avatarUrl != null) {
        await _deleteOldImage(avatarUrl!);
      }

      // Upload to Supabase
      final url = await _uploadImage(File(pickedImage.path));
      if (url != null) {
        await _updateUserProfile(url);
        setState(() {
          avatarUrl = url;
          _pickedImageFile = null; // Clear local file once uploaded
          isLoading = false;
        });
      } else {
        setState(() {
          _pickedImageFile = null;
          isLoading = false;
        });
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload image')),
          );
        }
      }
    }
  }

  Future<String?> _uploadImage(File image) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;

      final fileName = 'profile_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage
          .from('profile-images')
          .upload(fileName, image);

      return supabase.storage.from('profile-images').getPublicUrl(fileName);
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _updateUserProfile(String imageUrl) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Update user metadata (this is the primary storage)
      await supabase.auth.updateUser(
        UserAttributes(
          data: {'avatar_url': imageUrl},
        ),
      );

      // Try to update users table, but don't fail if it doesn't work
      try {
        await supabase.from('users').upsert({
          'id': user.id,
          'avatar_url': imageUrl,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (tableError) {
        print('Users table update failed (but auth metadata updated): $tableError');
        // Continue - auth metadata update is sufficient
      }
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow; // Re-throw to handle in calling function
    }
  }

  Future<void> _deleteOldImage(String imageUrl) async {
    try {
      // Extract filename from the URL
      final uri = Uri.parse(imageUrl);
      
      // Method 1: Try to extract from path segments
      String? fileName;
      final pathSegments = uri.pathSegments;
      
      // Look for the filename after 'profile-images'
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'profile-images' && i + 1 < pathSegments.length) {
          fileName = pathSegments[i + 1];
          break;
        }
      }
      
      // Method 2: If method 1 fails, try extracting from the full path
      if (fileName == null || fileName.isEmpty) {
        final path = uri.path;
        final profileImagesIndex = path.indexOf('/profile-images/');
        if (profileImagesIndex != -1) {
          fileName = path.substring(profileImagesIndex + '/profile-images/'.length);
        }
      }
      
      // Method 3: Last resort - get the last part of the URL
      if (fileName == null || fileName.isEmpty) {
        final parts = imageUrl.split('/');
        if (parts.isNotEmpty) {
          fileName = parts.last;
        }
      }

      print('Attempting to delete file: $fileName');
      print('Full URL: $imageUrl');
      print('URI path: ${uri.path}');
      print('Path segments: $pathSegments');

      if (fileName != null && fileName.isNotEmpty) {
        await supabase.storage
            .from('profile-images')
            .remove([fileName]);
        print('Successfully deleted image: $fileName');
      } else {
        print('Could not extract filename from URL');
      }
    } catch (e) {
      print('Error deleting old image: $e');
      print('Error details: ${e.toString()}');
    }
  }

  Future<void> _deleteProfileImage() async {
    if (avatarUrl == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      // Delete image from storage
      await _deleteOldImage(avatarUrl!);
      
      // Update user profile to remove avatar URL
      final user = supabase.auth.currentUser;
      if (user != null) {
        // Update user metadata
        await supabase.auth.updateUser(
          UserAttributes(
            data: {'avatar_url': null},
          ),
        );

        // Update users table
        try {
          await supabase.from('users').upsert({
            'id': user.id,
            'avatar_url': null,
            'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (tableError) {
          print('Error updating users table: $tableError');
          // Continue even if table update fails
        }
      }

      setState(() {
        avatarUrl = null;
        _pickedImageFile = null;
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile image deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error in _deleteProfileImage: $e');
      setState(() {
        isLoading = false;
      });
      
      // Still update UI even if storage deletion failed
      setState(() {
        avatarUrl = null;
        _pickedImageFile = null;
      });
      
      // Update user profile even if storage deletion failed
      try {
        final user = supabase.auth.currentUser;
        if (user != null) {
          await supabase.auth.updateUser(
            UserAttributes(data: {'avatar_url': null}),
          );
        }
      } catch (profileError) {
        print('Error updating profile after storage deletion failed: $profileError');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image removed from profile (storage cleanup may have failed)'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _loadProfileImage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      // First try to get from user metadata
      String? imageUrl = user.userMetadata?['avatar_url'] as String?;
      
      // If not found in metadata, try from users table
      if (imageUrl == null) {
        final response = await supabase
            .from('users')
            .select('avatar_url')
            .eq('id', user.id)
            .maybeSingle();
        
        imageUrl = response?['avatar_url'] as String?;
      }

      setState(() {
        avatarUrl = imageUrl;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading profile image: $e');
      setState(() {
        isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              UserAvatar(
                radius: 70,
                avatarUrl: _pickedImageFile !=null ? null : avatarUrl,
                iconSize: 80,
                backgroundColor: Theme.of(context).colorScheme.background,
              ),
              if (isLoading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.background,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: const Color.fromRGBO(255, 109, 77, 1.0),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          TextButton(
            onPressed: isLoading ? null : _showImageOptionsBottomSheet,
            child: Text(
              'Edit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold , fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}