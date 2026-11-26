// Built-in expense categories, custom-icon palette, and label → category lookup.

import 'package:waffr/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

/// A category's label, icon and chart colors.
class ExpenseCategory {
  /// Name stored on expenses and shown on tiles.
  final String label;

  /// Tile and list icon.
  final IconData icon;

  /// Chart color on the light theme.
  final Color color;

  /// Chart color on the dark theme: the same hue, a little lighter.
  final Color darkColor;

  /// A category.
  const ExpenseCategory({
    required this.label,
    required this.icon,
    required this.color,
    required this.darkColor,
  });
}

/// Grid order for "add expense". Chart colors are an earthy set that sits
/// with the app's green: terracotta, teal, berry, ochre, red, violet and sky
/// blue. Each hue has its own lightness so neighbouring slices stay
/// apart, also for color-blind readers.
const List<ExpenseCategory> expenseCategories = [
  ExpenseCategory(
    label: 'طعام',
    icon: AppIcons.burger,
    color: Color(0xFFDD8461),
    darkColor: Color(0xFFF19773),
  ),
  ExpenseCategory(
    label: 'مواصلات',
    icon: AppIcons.bus,
    color: Color(0xFF00828D),
    darkColor: Color(0xFF289DA9),
  ),
  ExpenseCategory(
    label: 'تسوق',
    icon: AppIcons.shoppingBag,
    color: Color(0xFFAC5371),
    darkColor: Color(0xFFCA6E8C),
  ),
  ExpenseCategory(
    label: 'فواتير',
    icon: AppIcons.receipt,
    color: Color(0xFFDBB155),
    darkColor: Color(0xFFE8C773),
  ),
  // A clear red, apart from the brand green that marks good news and from
  // the heart of the health score.
  ExpenseCategory(
    label: 'صحة',
    icon: AppIcons.stethoscope,
    color: Color(0xFFC8453F),
    darkColor: Color(0xFFE2655E),
  ),
  ExpenseCategory(
    label: 'ترفيه',
    icon: AppIcons.gamepad,
    color: Color(0xFF6A57A4),
    darkColor: Color(0xFF8371C1),
  ),
  ExpenseCategory(
    label: 'تعليم',
    icon: AppIcons.education,
    color: Color(0xFF7CAFE8),
    darkColor: Color(0xFF88BCF6),
  ),
];

/// Label of the "add your own" tile.
const String customCategoryActionLabel = 'مخصص';

/// The "add your own" tile at the end of the grid.
const ExpenseCategory customCategoryAction = ExpenseCategory(
  label: customCategoryActionLabel,
  icon: AppIcons.add,
  color: Color(0xFF9A9388),
  darkColor: Color(0xFFA39D91),
);

/// Expenses with no category, or «أخرى».
const ExpenseCategory fallbackCategory = ExpenseCategory(
  label: 'أخرى',
  icon: AppIcons.more,
  color: Color(0xFF9A9388),
  darkColor: Color(0xFFA39D91),
);

/// Payment methods; the first is the default.
const List<String> paymentMethods = ['نقداً', 'بطاقة'];

/// Icons users can pick when creating a custom category.
///
/// A saved category stores its icon as an index into this list, so entries
/// are only ever appended: never reorder or remove one. Slot 11 was a second
/// shopping cart and now shows a basket; slot 32 was the piggy bank and now
/// shows the Waffr wallet that replaced it. The picker shows the slots in
/// themed groups ([customCategoryIconGroups]).
const List<IconData> customCategoryIconChoices = [
  // 0-38: the original set.
  AppIcons.food,
  AppIcons.burger,
  AppIcons.coffee,
  AppIcons.shoppingCart,
  AppIcons.bus,
  AppIcons.car,
  AppIcons.taxi,
  AppIcons.bike,
  AppIcons.fuel,
  AppIcons.plane,
  AppIcons.shoppingBag,
  AppIcons.shoppingBasket,
  AppIcons.shirt,
  AppIcons.home,
  AppIcons.droplet,
  AppIcons.lightbulb,
  AppIcons.receipt,
  AppIcons.wifi,
  AppIcons.phone,
  AppIcons.tv,
  AppIcons.hospital,
  AppIcons.pill,
  AppIcons.education,
  AppIcons.book,
  AppIcons.briefcase,
  AppIcons.football,
  AppIcons.medal,
  AppIcons.dumbbell,
  AppIcons.gamepad,
  AppIcons.movie,
  AppIcons.wallet,
  AppIcons.creditCard,
  AppIcons.savings,
  AppIcons.baby,
  AppIcons.pet,
  AppIcons.gift,
  AppIcons.scissors,
  AppIcons.wrench,
  AppIcons.celebration,
  // 39 on: added later.
  AppIcons.pizza,
  AppIcons.croissant,
  AppIcons.sandwich,
  AppIcons.drumstick,
  AppIcons.beef,
  AppIcons.soup,
  AppIcons.salad,
  AppIcons.apple,
  AppIcons.milk,
  AppIcons.egg,
  AppIcons.cookie,
  AppIcons.iceCream,
  AppIcons.soda,
  AppIcons.cookingPot,
  AppIcons.restaurant,
  AppIcons.motorbike,
  AppIcons.train,
  AppIcons.tram,
  AppIcons.ship,
  AppIcons.truck,
  AppIcons.parking,
  AppIcons.luggage,
  AppIcons.hotel,
  AppIcons.tent,
  AppIcons.palmTree,
  AppIcons.mapPin,
  AppIcons.ticket,
  AppIcons.umbrella,
  AppIcons.building,
  AppIcons.key,
  AppIcons.sofa,
  AppIcons.bed,
  AppIcons.lamp,
  AppIcons.washingMachine,
  AppIcons.fridge,
  AppIcons.hammer,
  AppIcons.paintRoller,
  AppIcons.plug,
  AppIcons.electricity,
  AppIcons.flame,
  AppIcons.router,
  AppIcons.sprout,
  AppIcons.flower,
  AppIcons.footprints,
  AppIcons.watch,
  AppIcons.gem,
  AppIcons.glasses,
  AppIcons.perfume,
  AppIcons.bath,
  AppIcons.brush,
  AppIcons.sparkles,
  AppIcons.stethoscope,
  AppIcons.syringe,
  AppIcons.heartPulse,
  AppIcons.bandage,
  AppIcons.swimming,
  AppIcons.school,
  AppIcons.backpack,
  AppIcons.library,
  AppIcons.edit,
  AppIcons.laptop,
  AppIcons.monitor,
  AppIcons.printer,
  AppIcons.hardHat,
  AppIcons.family,
  AppIcons.cake,
  AppIcons.charity,
  AppIcons.handHeart,
  AppIcons.handCoins,
  AppIcons.mosque,
  AppIcons.cat,
  AppIcons.dog,
  AppIcons.fish,
  AppIcons.bone,
  AppIcons.music,
  AppIcons.headphones,
  AppIcons.camera,
  AppIcons.popcorn,
  AppIcons.puzzle,
  AppIcons.dice,
  AppIcons.trophy,
  AppIcons.bank,
  AppIcons.coins,
  AppIcons.percent,
  AppIcons.scale,
  AppIcons.insurance,
  AppIcons.fileText,
  AppIcons.cloud,
  AppIcons.repeat,
];

/// How many icons the picker had before it grew. Categories saved without
/// an icon index (old lists, labels only known from synced expenses) get an
/// icon from the label's hash modulo this count, so they keep the icon they
/// always showed.
const int legacyCustomIconCount = 39;

/// The picker's sections: an Arabic title and the [customCategoryIconChoices]
/// slots it shows. Every slot appears in exactly one group.
const List<({String title, List<int> slots})> customCategoryIconGroups = [
  (
    title: 'طعام وشراب',
    slots: [
      0,
      1,
      2,
      39,
      40,
      41,
      42,
      43,
      44,
      45,
      46,
      47,
      48,
      49,
      50,
      51,
      52,
      53,
    ],
  ),
  (
    title: 'تسوّق وعناية',
    slots: [3, 11, 10, 12, 82, 83, 84, 85, 86, 87, 88, 36, 89],
  ),
  (
    title: 'مواصلات وسفر',
    slots: [
      4,
      5,
      6,
      7,
      54,
      8,
      55,
      56,
      57,
      58,
      59,
      9,
      60,
      61,
      62,
      63,
      64,
      65,
      66,
    ],
  ),
  (
    title: 'البيت والفواتير',
    slots: [
      13,
      67,
      68,
      69,
      70,
      71,
      72,
      73,
      74,
      75,
      37,
      76,
      77,
      14,
      78,
      15,
      16,
      17,
      79,
      18,
      19,
      80,
      81,
    ],
  ),
  (title: 'صحة ورياضة', slots: [20, 90, 21, 91, 92, 93, 27, 94, 25, 26]),
  (title: 'تعليم وعمل', slots: [22, 95, 96, 23, 97, 98, 99, 100, 101, 24, 102]),
  (
    title: 'عائلة وعطاء',
    slots: [103, 33, 35, 104, 38, 105, 106, 107, 108, 34, 109, 110, 111, 112],
  ),
  (title: 'ترفيه', slots: [28, 29, 113, 114, 115, 116, 117, 118, 119]),
  (
    title: 'مال واشتراكات',
    slots: [30, 31, 32, 120, 121, 122, 123, 124, 125, 126, 127],
  ),
];

/// Chart slices for added categories: more hues from the same earthy
/// family. Saved categories keep their slot index, so the order is fixed and
/// new colors are only appended.
const List<Color> customCategoryColors = [
  Color(0xFF848D42),
  Color(0xFFA24B36),
  Color(0xFF4EA4CA),
  Color(0xFFD48490),
  Color(0xFF41A083),
  Color(0xFF6D4177),
  Color(0xFFC9A471),
  Color(0xFF596DB2),
  Color(0xFFDD766F),
  Color(0xFF4C682E),
  Color(0xFFAD98D5),
  Color(0xFF57B6B6),
  Color(0xFF2E6F9E),
  Color(0xFF9C4F96),
  Color(0xFFB8902C),
  Color(0xFF5F7A8A),
  Color(0xFFCF6A3A),
  Color(0xFF3E8E6E),
];

/// How many colors the palette had before it grew. Like
/// [legacyCustomIconCount], it keeps hashed colors where they always were.
const int legacyCustomColorCount = 12;

/// [customCategoryColors] for the dark theme, slot for slot.
const List<Color> customCategoryDarkColors = [
  Color(0xFF90994E),
  Color(0xFFBC634D),
  Color(0xFF5BB0D7),
  Color(0xFFE2909C),
  Color(0xFF4FAC8F),
  Color(0xFF855890),
  Color(0xFFD6B17D),
  Color(0xFF6F85CC),
  Color(0xFFEB827B),
  Color(0xFF637F45),
  Color(0xFFBAA4E2),
  Color(0xFF64C3C3),
  Color(0xFF4A8BBA),
  Color(0xFFB667B0),
  Color(0xFFD1A845),
  Color(0xFF7D97A7),
  Color(0xFFE5824F),
  Color(0xFF52A783),
];

/// Wired by CategoryStore so charts/reports resolve saved custom icons.
ExpenseCategory? Function(String label)? customCategoryLookup;

/// [index] kept inside [customCategoryIconChoices].
int clampCustomIconIndex(int index) {
  if (customCategoryIconChoices.isEmpty) return 0;
  return index.clamp(0, customCategoryIconChoices.length - 1).toInt();
}

/// [index] kept inside [customCategoryColors].
int clampCustomColorIndex(int index) {
  if (customCategoryColors.isEmpty) return 0;
  return index.clamp(0, customCategoryColors.length - 1).toInt();
}

/// First palette slot not already taken; wraps only after every color is used.
int nextCustomColorIndex(Iterable<int> used) {
  final taken = used.toSet();
  for (var i = 0; i < customCategoryColors.length; i++) {
    if (!taken.contains(i)) return i;
  }
  return taken.length % customCategoryColors.length;
}

/// Builds a custom category. [colorIndex] keeps a saved color; otherwise the
/// label hash picks one from the added-category palette.
ExpenseCategory customCategoryNamed(
  String label, {
  int? iconIndex,
  int? colorIndex,
}) {
  final hash = label.hashCode.abs();
  final resolvedIcon = iconIndex == null
      ? hash % legacyCustomIconCount
      : clampCustomIconIndex(iconIndex);
  final resolvedColor = colorIndex == null
      ? hash % legacyCustomColorCount
      : clampCustomColorIndex(colorIndex);

  return ExpenseCategory(
    label: label,
    icon: customCategoryIconChoices[resolvedIcon],
    color: customCategoryColors[resolvedColor],
    darkColor: customCategoryDarkColors[resolvedColor],
  );
}

/// Built-in first, then custom lookup, otherwise a hashed custom row.
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

/// The chart color of [label] for the current theme.
Color categoryChartColor(BuildContext context, String? label) {
  final category = categoryFor(label);
  return Theme.of(context).brightness == Brightness.dark
      ? category.darkColor
      : category.color;
}
