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

// Grid order for "add expense"; olive/cream palette matches the Waffer theme.
const List<ExpenseCategory> expenseCategories = [
  ExpenseCategory(
    label: 'طعام',
    icon: Icons.lunch_dining_outlined,
    color: Color(0xFFB8924A),
  ),
  ExpenseCategory(
    label: 'مواصلات',
    icon: Icons.directions_bus_outlined,
    color: Color(0xFF5F8F82),
  ),
  ExpenseCategory(
    label: 'تسوق',
    icon: Icons.shopping_bag_outlined,
    color: Color(0xFFC4956A),
  ),
  ExpenseCategory(
    label: 'فواتير',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFFA89B55),
  ),
  ExpenseCategory(
    label: 'صحة',
    icon: Icons.favorite_border_rounded,
    color: Color(0xFFB07A6E),
  ),
  ExpenseCategory(
    label: 'ترفيه',
    icon: Icons.sports_esports_outlined,
    color: Color(0xFF7D9160),
  ),
  ExpenseCategory(
    label: 'تعليم',
    icon: Icons.school_outlined,
    color: Color(0xFF4F7D52),
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

// Muted olive, gold, and clay tones for chart slices of added categories.
// Kept apart from the built-in swatches so percentage charts stay readable.
const List<Color> customCategoryColors = [
  Color(0xFF6E8F4E),
  Color(0xFFC4A15A),
  Color(0xFF8C6A45),
  Color(0xFF4E7A62),
  Color(0xFFA68462),
  Color(0xFF7A8A48),
  Color(0xFF9A7048),
  Color(0xFF5C7350),
  Color(0xFFB89A6A),
  Color(0xFF6A5E42),
  Color(0xFF8E9A68),
  Color(0xFFA07858),
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
