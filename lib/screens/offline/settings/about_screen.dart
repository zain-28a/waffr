// "عن وفّر": an empty page for now, opened from the settings support group.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/glass/aurora_backdrop.dart';

/// The About page. Intentionally has no content yet.
class AboutScreen extends StatelessWidget {
  /// Creates an [AboutScreen].
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: const WaffrBackHeader(title: 'عن وفّر'),
      body: const AuroraPage(child: SizedBox.expand()),
    );
  }
}
