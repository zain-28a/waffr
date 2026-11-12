// Circular profile icon: crossed out for guests, plain when signed in.
import 'package:waffr/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

/// Person icon on an accent circle. There are no profile photos.
class ProfileAvatar extends StatelessWidget {
  /// Icon and tint color.
  final Color accent;

  /// Circle radius; the icon is as large.
  final double radius;

  /// False draws the crossed-out guest icon.
  final bool signedIn;

  /// Creates a [ProfileAvatar].
  const ProfileAvatar({
    super.key,
    required this.accent,
    required this.signedIn,
    this.radius = 36,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: accent.withValues(alpha: 0.15),
      child: Icon(
        signedIn ? AppIcons.user : AppIcons.userOff,
        color: accent,
        size: radius,
      ),
    );
  }
}
