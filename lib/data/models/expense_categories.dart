// Built-in expense categories, custom-icon palette, and label → category lookup.

import 'package:flutter/material.dart';

class ExpenseCategory {
  final String label;
  final IconData icon;
  final Color color;

  const ExpenseCategory({
    required this.label,
    required this.icon,
    required this.color,
  });
}

// Grid order for "add expense". Chart colors are distinct hues anchored on the
// Waffer green so neighbouring donut slices stay easy to tell apart.
const List<ExpenseCategory> expenseCategories = [
  ExpenseCategory(
    label: 'طعام',
    icon: Icons.lunch_dining_outlined,
    color: Color(0xFF2E7D4F),
  ),
  ExpenseCategory(
    label: 'مواصلات',
    icon: Icons.directions_bus_outlined,
    color: Color(0xFF3F88C5),
  ),
  ExpenseCategory(
    label: 'تسوق',
    icon: Icons.shopping_bag_outlined,
    color: Color(0xFFE39B3A),
  ),
  ExpenseCategory(
    label: 'فواتير',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFFD1603D),
  ),
  ExpenseCategory(
    label: 'صحة',
    icon: Icons.favorite_border_rounded,
    color: Color(0xFFC2477A),
  ),
  ExpenseCategory(
    label: 'ترفيه',
    icon: Icons.sports_esports_outlined,
    color: Color(0xFF8A63C8),
  ),
  ExpenseCategory(
    label: 'تعليم',
    icon: Icons.school_outlined,
    color: Color(0xFF2BA39A),
  ),
];

const String customCategoryActionLabel = 'مخصص';

const ExpenseCategory customCategoryAction = ExpenseCategory(
  label: customCategoryActionLabel,
  icon: Icons.add_rounded,
  color: Color(0xFF9A9388),
);

const ExpenseCategory fallbackCategory = ExpenseCategory(
  label: 'أخرى',
  icon: Icons.more_horiz_rounded,
  color: Color(0xFF9A9388),
);

const List<String> paymentMethods = ['نقداً', 'بطاقة'];

// Icons users can pick when creating a custom category.
const List<IconData> customCategoryIconChoices = [
  Icons.restaurant_outlined,
  Icons.lunch_dining_outlined,
  Icons.local_cafe_outlined,
  Icons.local_grocery_store_outlined,
  Icons.directions_bus_outlined,
  Icons.directions_car_outlined,
  Icons.local_taxi_outlined,
  Icons.two_wheeler_outlined,
  Icons.local_gas_station_outlined,
  Icons.flight_outlined,
  Icons.shopping_bag_outlined,
  Icons.shopping_cart_outlined,
  Icons.checkroom_outlined,
  Icons.home_outlined,
  Icons.water_drop_outlined,
  Icons.lightbulb_outline_rounded,
  Icons.receipt_long_outlined,
  Icons.wifi_outlined,
  Icons.phone_android_outlined,
  Icons.tv_outlined,
  Icons.local_hospital_outlined,
  Icons.local_pharmacy_outlined,
  Icons.school_outlined,
  Icons.menu_book_outlined,
  Icons.work_outline_rounded,
  Icons.sports_soccer_outlined,
  Icons.sports_outlined,
  Icons.fitness_center_outlined,
  Icons.sports_esports_outlined,
  Icons.movie_outlined,
  Icons.account_balance_wallet_outlined,
  Icons.credit_card_outlined,
  Icons.savings_outlined,
  Icons.child_care_outlined,
  Icons.pets_outlined,
  Icons.card_giftcard_outlined,
  Icons.content_cut_outlined,
  Icons.build_outlined,
  Icons.celebration_outlined,
];

// Chart slices for added categories. Separate hues from the built-in swatches
// so percentage charts stay readable. Saved categories keep their slot index.
const List<Color> customCategoryColors = [
  Color(0xFF7CB342),
  Color(0xFF5C6BC0),
  Color(0xFFF2C14E),
  Color(0xFFA1665E),
  Color(0xFF26A0C9),
  Color(0xFFE07B91),
  Color(0xFF6D8B3A),
  Color(0xFFB07CC6),
  Color(0xFF4E9E7D),
  Color(0xFFCF8B4F),
  Color(0xFF5A7EA6),
  Color(0xFFB5A642),
];

// Wired by CategoryStore so charts/reports resolve saved custom icons.
ExpenseCategory? Function(String label)? customCategoryLookup;

int clampCustomIconIndex(int index) {
  if (customCategoryIconChoices.isEmpty) return 0;
  return index.clamp(0, customCategoryIconChoices.length - 1).toInt();
}

int clampCustomColorIndex(int index) {
  if (customCategoryColors.isEmpty) return 0;
  return index.clamp(0, customCategoryColors.length - 1).toInt();
}

// First palette slot not already taken; wraps only after every color is used.
int nextCustomColorIndex(Iterable<int> used) {
  final taken = used.toSet();
  for (var i = 0; i < customCategoryColors.length; i++) {
    if (!taken.contains(i)) return i;
  }
  return taken.length % customCategoryColors.length;
}

// Builds a custom category. [colorIndex] keeps a saved color; otherwise the
// label hash picks one from the added-category palette.
ExpenseCategory customCategoryNamed(
  String label, {
  int? iconIndex,
  int? colorIndex,
}) {
  final hash = label.hashCode.abs();
  final resolvedIcon = iconIndex == null
      ? hash % customCategoryIconChoices.length
      : clampCustomIconIndex(iconIndex);
  final resolvedColor = colorIndex == null
      ? hash % customCategoryColors.length
      : clampCustomColorIndex(colorIndex);

  return ExpenseCategory(
    label: label,
    icon: customCategoryIconChoices[resolvedIcon],
    color: customCategoryColors[resolvedColor],
  );
}

// Built-in first, then custom lookup, otherwise a hashed custom row.
ExpenseCategory categoryFor(String? label) {
  if (label == null || label.isEmpty) return fallbackCategory;

  for (final item in expenseCategories) {
    if (item.label == label) return item;
  }

  if (label == fallbackCategory.label) return fallbackCategory;

  final custom = customCategoryLookup?.call(label);
  if (custom != null) return custom;

  return customCategoryNamed(label);
}

// Slightly lightens category colors in dark mode for chart readability.
Color categoryChartColor(BuildContext context, String? label) {
  final base = categoryFor(label).color;
  if (Theme.of(context).brightness != Brightness.dark) {
    return base;
  }
  return Color.lerp(base, const Color(0xFFE8F0E4), 0.18)!;
}
