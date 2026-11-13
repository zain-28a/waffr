// SwipeActions: a sideways drag uncovers the actions, a tap on one runs it
// and closes the row, and a disabled row does not move.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/widgets/containers/swipe_actions.dart';

void main() {
  Widget app({required VoidCallback onEdit, bool enabled = true}) =>
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SwipeActions(
              enabled: enabled,
              actions: [
                SwipeAction(icon: Icons.edit, label: 'تعديل', onTap: onEdit),
                SwipeAction(
                  icon: Icons.delete,
                  label: 'حذف',
                  destructive: true,
                  onTap: () {},
                ),
              ],
              child: const SizedBox(
                height: 60,
                width: double.infinity,
                child: Text('row'),
              ),
            ),
          ),
        ),
      );

  testWidgets('a swipe uncovers the actions and a tap runs one', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(app(onEdit: () => edits++));
    expect(find.text('تعديل'), findsNothing);

    // In RTL the row moves right, toward the start edge.
    await tester.drag(find.text('row'), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(find.text('تعديل'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);

    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(find.text('تعديل'), findsNothing);
  });

  testWidgets('a disabled row stays shut', (tester) async {
    await tester.pumpWidget(app(onEdit: () {}, enabled: false));
    await tester.drag(find.text('row'), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(find.text('تعديل'), findsNothing);
  });
}
