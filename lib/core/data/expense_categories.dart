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

/// ترتيب التصنيفات كما يظهر في شبكة "إضافة مصروف".
/// لوحة زيتون وكريم مترابطة مع ثيم وفر.
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

/// شعارات عملية لتصنيفات المصروف اليومية.
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

const List<Color> _customCategoryColors = [
  Color(0xFF8A6B4A),
  Color(0xFF6B8F71),
  Color(0xFFA67C5B),
  Color(0xFF5B7D8A),
  Color(0xFF8B6B7A),
  Color(0xFF7A8B5B),
];

/// يربطه CategoryStore حتى تظهر الشعارات المحفوظة في الرسوم والتقارير.
ExpenseCategory? Function(String label)? customCategoryLookup;

int clampCustomIconIndex(int index) {
  if (customCategoryIconChoices.isEmpty) return 0;
  return index.clamp(0, customCategoryIconChoices.length - 1).toInt();
}

ExpenseCategory customCategoryNamed(String label, {int? iconIndex}) {
  final colorIndex = label.hashCode.abs();
  final resolvedIcon = iconIndex == null
      ? colorIndex % customCategoryIconChoices.length
      : clampCustomIconIndex(iconIndex);

  return ExpenseCategory(
    label: label,
    icon: customCategoryIconChoices[resolvedIcon],
    color: _customCategoryColors[colorIndex % _customCategoryColors.length],
  );
}

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

Color categoryChartColor(BuildContext context, String? label) {
  final base = categoryFor(label).color;
  if (Theme.of(context).brightness != Brightness.dark) {
    return base;
  }
  return Color.lerp(base, const Color(0xFFE8F0E4), 0.18)!;
}
