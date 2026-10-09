import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepr/core/domain/money.dart';
import 'package:keepr/features/receipts/domain/entities/receipt.dart';
import 'package:keepr/features/receipts/presentation/review/item_editor_sheet.dart';

void main() {
  testWidgets('item editor validates and returns the edited item with warranty', (tester) async {
    LineItem? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showItemEditor(
                context,
                const LineItem(id: 'i1', name: '', quantity: 1, unitPrice: Money.zero('PKR')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Name is required.
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Enter the item name'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Item name'), 'Air fryer');
    await tester.enterText(find.widgetWithText(TextField, 'Unit price'), '32,500');
    await tester.tap(find.byTooltip('More'));
    await tester.tap(find.text('1 yr'));
    await tester.pump();
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.name, 'Air fryer');
    expect(result!.unitPrice, const Money(3250000, 'PKR'));
    expect(result!.quantity, 2);
    expect(result!.warranty?.months, 12);
  });
}
