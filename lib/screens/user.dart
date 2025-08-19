import 'package:chat_app/screens/auth.dart';
import 'package:chat_app/widgets/user_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

final supabase = Supabase.instance.client;

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  String? userName;
  String? userEmail;
  bool isLoading = true;
  bool isUploadingPhoto = false;
  List<Map<String, dynamic>> userPhotos = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserPhotos();
  }

  Future<void> _loadUserData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // Fetch user data from the users table
        final response = await supabase
            .from('users')
            .select('username, email, avatar_url')
            .eq('id', user.id)
            .single();

        setState(() {
          userName = response['username'] ?? 'Unknown User';
          userEmail = response['email'] ?? user.email ?? 'No email';
          isLoading = false;
        });
      }
    } catch (e) {
      // Fallback to auth user data if users table fetch fails
      final user = supabase.auth.currentUser;
      setState(() {
        userName = user?.email?.split('@')[0] ?? 'Unknown User';
        userEmail = user?.email ?? 'No email';
        isLoading = false;
      });
    }
  }

  Future<void> _loadUserPhotos() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('user_photos')
            .select('*')
            .eq('user_id', user.id)
            .order('created_at', ascending: false);

        setState(() {
          userPhotos = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('Error loading photos: $e');
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          isUploadingPhoto = true;
        });

        final user = supabase.auth.currentUser;
        if (user == null) return;

        // Upload image to Supabase Storage
        final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final filePath = '${user.id}/$fileName';

        await supabase.storage
            .from('user-photos')
            .upload(filePath, File(image.path));

        // Get public URL
        final imageUrl = supabase.storage
            .from('user-photos')
            .getPublicUrl(filePath);

        // Save photo record to database
        await supabase.from('user_photos').insert({
          'user_id': user.id,
          'photo_url': imageUrl,
          'file_path': filePath,
          'created_at': DateTime.now().toIso8601String(),
        });

        // Reload photos
        await _loadUserPhotos();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo uploaded successfully!'),
            backgroundColor: Color.fromRGBO(255, 109, 77, 1.0),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isUploadingPhoto = false;
      });
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    try {
      // Delete from storage
      await supabase.storage
          .from('user-photos')
          .remove([photo['file_path']]);

      // Delete from database
      await supabase
          .from('user_photos')
          .delete()
          .eq('id', photo['id']);

      // Reload photos
      await _loadUserPhotos();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo deleted successfully!'),
          backgroundColor: Color.fromRGBO(255, 109, 77, 1.0),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showPhotoOptions(Map<String, dynamic> photo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete Photo',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showDeletePhotoDialog(photo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeletePhotoDialog(Map<String, dynamic> photo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Text(
          'Delete Photo',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 25
          ),
        ),
        content: Text(
          'Are you sure you want to delete this photo?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            fontSize: 20
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color.fromRGBO(255, 109, 77, 1.0)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color.fromRGBO(255, 109, 77, 1.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _deletePhoto(photo);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenPhoto(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color.fromRGBO(255, 109, 77, 1.0),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotosSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Photos',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: isUploadingPhoto ? null : _pickAndUploadImage,
                  icon: isUploadingPhoto
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_a_photo, size: 18),
                  label: Text(isUploadingPhoto ? 'Uploading...' : 'Add Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromRGBO(255, 109, 77, 1.0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (userPhotos.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No photos yet',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add your first photo to get started',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: userPhotos.length,
                itemBuilder: (context, index) {
                  final photo = userPhotos[index];
                  return GestureDetector(
                    onTap: () => _showFullScreenPhoto(photo['photo_url']),
                    onLongPress: () => _showPhotoOptions(photo),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          photo['photo_url'],
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color.fromRGBO(255, 109, 77, 1.0),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: const Icon(
                                Icons.error_outline,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogoutDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            'Log out',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 25
            ),
          ),
          content: Text(
            'Are you sure you want to log out?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 20
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: const Color.fromRGBO(255, 109, 77, 1.0),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromRGBO(255, 109, 77, 1.0), // orange
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              ),
              child: const Text(
                'Log out',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                final navigator = Navigator.of(context);
                await supabase.auth.signOut();
                navigator.pushReplacement(MaterialPageRoute(builder:(context) => const AuthScreen(),));
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            '! Delete Account',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
              fontSize: 25
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This action cannot be undone. This will permanently delete your account and remove all your data including:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '• All your messages\n• Profile information\n• All your photos',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: const Color.fromRGBO(255, 109, 77, 1.0),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromRGBO(255, 109, 77, 1.0), // orange
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteAccount();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount() async {
    // TODO: Implement account deletion functionality
    // For now, just show a placeholder message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Delete account functionality coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Profile Header Section
                  Container(
                    width: double.infinity,
                    color: const Color.fromRGBO(255, 109, 77, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80 , bottom: 20),
                      child: Column(
                        children: [
                          const Text(
                            'Profile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 30,),
                          const UserImagePicker(),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 8,),
                  
                  // Profile Info Section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16 , vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildInfoTile(
                      icon: Icons.person_outline,
                      title: 'Name',
                      subtitle: userName ?? '-',
                      onTap: null, // Not tappable
                    ),
                  ),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16 , vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildInfoTile(
                      icon: Icons.email_outlined,
                      title: 'Email',
                      subtitle: userEmail ?? '-',
                      onTap: null, // Not tappable
                    ),
                  ),

                  // Photos Section
                  _buildPhotosSection(),

                  // Action Buttons Section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16 , vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildActionTile(
                      icon: Icons.logout,
                      title: 'Log out',
                      color: const Color.fromRGBO(255, 109, 77, 1.0),
                      onTap: _showLogoutDialog,
                    ),
                  ),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16 , vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildActionTile(
                      icon: Icons.delete_forever,
                      title: 'Delete Account',
                      color: Theme.of(context).colorScheme.error,
                      onTap: _showDeleteAccountDialog,
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 109, 77, 1.0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: const Color.fromRGBO(255, 109, 77, 1.0),
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: color,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: color.withOpacity(0.5),
        size: 16,
      ),
    );
  }
}