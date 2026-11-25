// Expense category catalog: lookups for built-in, fallback and custom
// labels, palette clamping and slot assignment, and the chart color by theme.

import 'package:waffr/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/models/expense_categories.dart';

void main() {
  tearDown(() => customCategoryLookup = null);

  test('the catalog has unique labels and matching palettes', () {
    final labels = expenseCategories.map((item) => item.label).toList();
    expect(labels.toSet(), hasLength(labels.length));
    expect(labels, isNot(contains(fallbackCategory.label)));
    expect(customCategoryColors, hasLength(customCategoryDarkColors.length));
    expect(paymentMethods.first, 'نقداً');
  });

  test('categoryFor resolves built-ins, the fallback and blanks', () {
    expect(categoryFor('طعام'), same(expenseCategories.first));
    expect(categoryFor('أخرى'), same(fallbackCategory));
    expect(categoryFor(null), same(fallbackCategory));
    expect(categoryFor(''), same(fallbackCategory));
  });

  test('unknown labels use the lookup hook, else a hashed category', () {
    const custom = ExpenseCategory(
      label: 'قهوة',
      icon: AppIcons.coffee,
      color: Color(0xFF000001),
      darkColor: Color(0xFF000002),
    );
    customCategoryLookup = (label) => label == 'قهوة' ? custom : null;
    expect(categoryFor('قهوة'), same(custom));

    final hashed = categoryFor('شيء');
    expect(hashed.label, 'شيء');
    expect(customCategoryIconChoices, contains(hashed.icon));
    expect(customCategoryColors, contains(hashed.color));
    // Stable for the same label.
    expect(categoryFor('شيء').icon, hashed.icon);
  });

  test('customCategoryNamed keeps saved slots and clamps them', () {
    final named = customCategoryNamed('x', iconIndex: 1, colorIndex: 2);
    expect(named.icon, customCategoryIconChoices[1]);
    expect(named.color, customCategoryColors[2]);
    expect(named.darkColor, customCategoryDarkColors[2]);

    final clamped = customCategoryNamed('x', iconIndex: 999, colorIndex: -1);
    expect(clamped.icon, customCategoryIconChoices.last);
    expect(clamped.color, customCategoryColors.first);
  });

  test('saved icon slots keep their meaning as the picker grows', () {
    // Saved categories store an index, so the first slots never move.
    // Slot 11 (a duplicate cart) shows a basket and slot 32 (the piggy bank)
    // the Waffr wallet that replaced it; both keep their meaning.
    expect(customCategoryIconChoices[0], AppIcons.food);
    expect(customCategoryIconChoices[11], AppIcons.shoppingBasket);
    expect(customCategoryIconChoices[32], AppIcons.savings);
    expect(customCategoryIconChoices[38], AppIcons.celebration);
    expect(customCategoryIconChoices.length, greaterThan(100));
    expect(
      customCategoryIconChoices.toSet(),
      hasLength(customCategoryIconChoices.length),
      reason: 'no icon is offered twice',
    );
  });

  test('every picker slot sits in exactly one group', () {
    final slots = [
      for (final group in customCategoryIconGroups) ...group.slots,
    ];
    expect(slots.toSet(), hasLength(slots.length));
    expect(slots.toSet(), {
      for (var i = 0; i < customCategoryIconChoices.length; i++) i,
    });
  });

  test('hashed icons and colors ignore the grown palettes', () {
    // A label with no saved slots keeps the icon and color it always had.
    final hash = 'إيجار'.hashCode.abs();
    final named = customCategoryNamed('إيجار');
    expect(named.icon, customCategoryIconChoices[hash % legacyCustomIconCount]);
    expect(named.color, customCategoryColors[hash % legacyCustomColorCount]);
  });

  test('صحة no longer borrows the brand green or the health heart', () {
    final health = categoryFor('صحة');
    expect(health.icon, AppIcons.stethoscope);
    expect(health.color, isNot(const Color(0xFF4E8841)));
  });

  test('palette index helpers', () {
    expect(clampCustomIconIndex(-5), 0);
    expect(clampCustomIconIndex(3), 3);
    expect(clampCustomColorIndex(100), customCategoryColors.length - 1);

    expect(nextCustomColorIndex(const []), 0);
    expect(nextCustomColorIndex(const [0, 1, 3]), 2);
    final all = List.generate(customCategoryColors.length, (i) => i);
    expect(nextCustomColorIndex(all), 0, reason: 'wraps once all are used');
  });

  testWidgets('chart color follows the theme brightness', (tester) async {
    Future<Color> colorUnder(Brightness brightness) async {
      late Color color;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(brightness: brightness),
          child: Builder(
            builder: (context) {
              color = categoryChartColor(context, 'طعام');
              return const SizedBox();
            },
          ),
        ),
      );
      return color;
    }

    expect(await colorUnder(Brightness.light), expenseCategories.first.color);
    expect(
      await colorUnder(Brightness.dark),
      expenseCategories.first.darkColor,
    );
  });
}
