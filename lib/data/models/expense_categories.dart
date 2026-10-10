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

// Grid order for "add expense". Chart colors come from the Waffr reference
// palette: sky blue, dusty rose, cream yellow, lavender, peach and sage.
const List<ExpenseCategory> expenseCategories = [
  ExpenseCategory(
    label: 'طعام',
    icon: Icons.lunch_dining_outlined,
    color: Color(0xFFFEB599),
  ),
  ExpenseCategory(
    label: 'مواصلات',
    icon: Icons.directions_bus_outlined,
    color: Color(0xFFA9CFEC),
  ),
  ExpenseCategory(
    label: 'تسوق',
    icon: Icons.shopping_bag_outlined,
    color: Color(0xFFB67880),
  ),
  ExpenseCategory(
    label: 'فواتير',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFFFEE1B1),
  ),
  ExpenseCategory(
    label: 'صحة',
    icon: Icons.favorite_border_rounded,
    color: Color(0xFF7C9687),
  ),
  ExpenseCategory(
    label: 'ترفيه',
    icon: Icons.sports_esports_outlined,
    color: Color(0xFF9D90B0),
  ),
  ExpenseCategory(
    label: 'تعليم',
    icon: Icons.school_outlined,
    color: Color(0xFF7FAED3),
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

// Chart slices for added categories: deeper and lighter shades of the same
// reference palette. Saved categories keep their slot index.
const List<Color> customCategoryColors = [
  Color(0xFF5B7B69),
  Color(0xFF93585F),
  Color(0xFFF2C97E),
  Color(0xFF7A6C95),
  Color(0xFFF08F6E),
  Color(0xFFCFE5F6),
  Color(0xFFA9C2B3),
  Color(0xFFD7A3AA),
  Color(0xFFC2B8D3),
  Color(0xFFFFD3C2),
  Color(0xFF5E8FB8),
  Color(0xFFD9B97A),
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

// The palette is already soft, so light and dark mode use the same swatch.
Color categoryChartColor(BuildContext context, String? label) {
  return categoryFor(label).color;
}
