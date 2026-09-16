import 'package:flutter/material.dart';

class PlaceholderScreen extends StatefulWidget {
  final String label;

  const PlaceholderScreen({super.key, required this.label});

  @override
  State<PlaceholderScreen> createState() => _PlaceholderScreenState();
}

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
