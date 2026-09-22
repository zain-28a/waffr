// Circular profile photo with optional camera badge when tappable.
import 'dart:io';

import 'package:flutter/material.dart';

/// Avatar from a local photo path, or a person icon placeholder.
class ProfileAvatar extends StatelessWidget {
  final String? photoPath;
  final Color accent;
  final double radius;
  final bool placeholder;
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    required this.accent,
    this.photoPath,
    this.radius = 36,
    this.placeholder = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoPath != null && photoPath!.isNotEmpty;
    final cacheKey = hasPhoto
        ? File(photoPath!).lastModifiedSync().millisecondsSinceEpoch.toString()
        : 'none';
    final avatar = CircleAvatar(
      key: ValueKey(cacheKey),
      radius: radius,
      backgroundColor: accent.withValues(alpha: 0.15),
      backgroundImage: hasPhoto ? FileImage(File(photoPath!)) : null,
      child: hasPhoto
          ? null
          : Icon(
              placeholder
                  ? Icons.person_off_outlined
                  : Icons.person_outline_rounded,
              color: accent,
              size: radius,
            ),
    );

    if (onTap == null) return avatar;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            left: -2,
            bottom: -2,
            child: Container(
              width: radius * 0.72,
              height: radius * 0.72,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                size: radius * 0.34,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
