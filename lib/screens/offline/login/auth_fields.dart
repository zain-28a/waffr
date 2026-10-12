import 'package:flutter/material.dart';

// Shared field chrome for login and register screens.

InputDecoration authFieldDecoration({
  required String hint,
  required Color fillColor,
  required Color textSecondary,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6)),
    filled: true,
    fillColor: fillColor,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );
}

class AuthFieldLabel extends StatelessWidget {
  final String text;
  final Color color;

  /// Creates a [AuthFieldLabel].
  const AuthFieldLabel({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
    );
  }
}
