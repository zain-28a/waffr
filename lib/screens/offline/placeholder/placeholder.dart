import 'package:flutter/material.dart';

// Minimal keep-alive stub used where a real tab screen is not ready yet.

class PlaceholderScreen extends StatefulWidget {
  final String label;

  /// Creates a [PlaceholderScreen].
  const PlaceholderScreen({super.key, required this.label});

  @override
  State<PlaceholderScreen> createState() => _PlaceholderScreenState();
}

/// State of [PlaceholderScreen].
class _PlaceholderScreenState extends State<PlaceholderScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Center(
      child: Text(widget.label, style: const TextStyle(fontSize: 18)),
    );
  }
}
