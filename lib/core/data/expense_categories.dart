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
const List<ExpenseCategory> expenseCategories = [
  ExpenseCategory(
    label: 'طعام',
    icon: Icons.lunch_dining_outlined,
    color: Color(0xFF2A8B60),
  ),
  ExpenseCategory(
    label: 'مواصلات',
    icon: Icons.directions_bus_outlined,
    color: Color(0xFF58A97F),
  ),
  ExpenseCategory(
    label: 'تسوق',
    icon: Icons.shopping_bag_outlined,
    color: Color(0xFF8BC7A8),
  ),
  ExpenseCategory(
    label: 'فواتير',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFFB6DDC8),
  ),
  ExpenseCategory(
    label: 'صحة',
    icon: Icons.favorite_border_rounded,
    color: Color(0xFF1F6B4A),
  ),
  ExpenseCategory(
    label: 'ترفيه',
    icon: Icons.sports_esports_outlined,
    color: Color(0xFF74B98F),
  ),
  ExpenseCategory(
    label: 'تعليم',
    icon: Icons.school_outlined,
    color: Color(0xFF9FD1B4),
  ),
  ExpenseCategory(
    label: 'أخرى',
    icon: Icons.more_horiz_rounded,
    color: Color(0xFFCBE4D6),
  ),
];

const List<String> paymentMethods = ['نقداً', 'بطاقة', 'عائلي'];

ExpenseCategory categoryFor(String? label) {
  return expenseCategories.firstWhere(
    (category) => category.label == label,
    orElse: () => expenseCategories.last,
  );
}
