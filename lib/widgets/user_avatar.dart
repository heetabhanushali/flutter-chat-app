import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    this.radius = 20,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final defaultBackgroundColor = backgroundColor ?? 
        Theme.of(context).colorScheme.primaryContainer;
    final defaultIconColor = iconColor ?? 
        const Color.fromRGBO(255, 109, 77, 1.0);
    final defaultIconSize = iconSize ?? radius;

    return CircleAvatar(
      radius: radius,
      backgroundColor: defaultBackgroundColor,
      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
      child: avatarUrl == null 
          ? Icon(
              Icons.person, 
              color: defaultIconColor, 
              size: defaultIconSize,
            )
          : null,
    );
  }
}