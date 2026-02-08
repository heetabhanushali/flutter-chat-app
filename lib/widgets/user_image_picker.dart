import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:chat_app/widgets/user_avatar.dart';
import 'package:chat_app/services/storage_service.dart';

class UserImagePicker extends StatefulWidget {
  const UserImagePicker({super.key});

  @override
  State<UserImagePicker> createState() => _UserImagePickerState();
}

class _UserImagePickerState extends State<UserImagePicker> {
  final _storageService = StorageService();
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
        try {
          await _storageService.deleteProfileImageFromStorage(avatarUrl!);
        } catch (e) {
          print('Error deleting old image: $e');
        }
      }

      // Upload new image
      try {
        final url = await _storageService.uploadProfileImage(File(pickedImage.path));
        if (url != null) {
          await _storageService.updateProfileAvatar(url);
          setState(() {
            avatarUrl = url;
            _pickedImageFile = null;
            isLoading = false;
          });
        } else {
          setState(() {
            _pickedImageFile = null;
            isLoading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to upload image')),
            );
          }
        }
      } catch (e) {
        setState(() {
          _pickedImageFile = null;
          isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error uploading image: $e')),
          );
        }
      }
    }
  }


  Future<void> _deleteProfileImage() async {
    if (avatarUrl == null) return;

    setState(() => isLoading = true);

    try {
      await _storageService.deleteProfileImage(avatarUrl!);

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
        avatarUrl = null;
        _pickedImageFile = null;
        isLoading = false;
      });

      // Try to clear avatar even if storage failed
      try {
        await _storageService.updateProfileAvatar(null);
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image removed from profile (storage cleanup may have failed)'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _loadProfileImage() async {
    setState(() => isLoading = true);

    try {
      final imageUrl = await _storageService.loadProfileImage();
      setState(() {
        avatarUrl = imageUrl;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading profile image: $e');
      setState(() => isLoading = false);
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