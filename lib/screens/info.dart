import 'package:chat_app/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:chat_app/services/user_service.dart';
import 'package:chat_app/services/storage_service.dart';

class InfoPage extends StatefulWidget {
  final Map<String, dynamic> recipientUser;
  
  const InfoPage({
    super.key,
    required this.recipientUser,
  });

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  final _userService = UserService();
  final _storageService = StorageService();
  String? userName;
  String? userEmail;
  String? avatarUrl;
  bool isLoading = false;
  List<Map<String, dynamic>> userPhotos = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserPhotos();
  }

  Future<void> _loadUserData() async {
    setState(() => isLoading = true);

    try {
      final recipientId = widget.recipientUser['id'];
      final data = await _userService.getUserById(recipientId);

      setState(() {
        userName = data['username'];
        avatarUrl = data['avatar_url'];
        userEmail = data['email'];
        isLoading = false;
      });
    } catch (error) {
      print('Error loading user data: $error');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadUserPhotos() async {
    try {
      final recipientId = widget.recipientUser['id'];
      final photos = await _storageService.loadUserPhotos(recipientId);

      setState(() {
        userPhotos = photos;
      });
    } catch (e) {
      print('Error loading photos: $e');
    }
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
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  color: const Color.fromRGBO(255, 109, 77, 1.0),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Photos',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 109, 77, 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${userPhotos.length}',
                    style: const TextStyle(
                      color: Color.fromRGBO(255, 109, 77, 1.0),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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
                      '${userName ?? 'This user'} hasn\'t posted any photos',
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
                      padding: const EdgeInsets.only(top: 70, bottom: 50),
                      child: Column(
                        children: [
                          // Header with back button
                          Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'User Info',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 56), // Balance the back button space
                            ],
                          ),
                          const SizedBox(height: 30),
                          // User Avatar
                          UserAvatar(
                            radius: 70,
                            avatarUrl: avatarUrl,
                            backgroundColor: Theme.of(context).colorScheme.background,
                            iconSize: 80,
                          ),
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
                      title: 'Username',
                      subtitle: userName ?? '-',
                      onTap: null,
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
                      onTap: null,
                    ),
                  ),

                  // Photos Section
                  _buildPhotosSection(),
                  
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
          color: const Color.fromRGBO(255, 109, 77, 0.1),
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
}