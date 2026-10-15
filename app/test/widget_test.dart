import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alvapay/main.dart';

void main() {
  testWidgets('dashboard fits a desktop workspace', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AlvaPayApp());

    expect(find.text('AlvaPay'), findsOneWidget);
    expect(find.text('New invoice'), findsOneWidget);
  });

  testWidgets('dashboard presents a clear, sandbox-labelled starting point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AlvaPayApp());

    expect(find.text('AlvaPay'), findsOneWidget);
    expect(find.text('Make room for\nyour next big thing.'), findsOneWidget);
    expect(find.text('SANDBOX'), findsOneWidget);
    expect(
      find.text(
        'Illustrative preview data · Connect your account for live payment records.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a user can save a reviewed manual invoice draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AlvaPayApp());

    await tester.tap(find.text('Create an invoice'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('invoice-client-name')),
      'Lumen Studio',
    );
    await tester.enterText(
      find.byKey(const Key('invoice-client-email')),
      'billing@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('invoice-description')),
      'Product illustration',
    );
    await tester.enterText(find.byKey(const Key('invoice-amount')), '840.50');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save invoice draft'));
    await tester.pumpAndSettle();

    expect(find.text('Lumen Studio'), findsOneWidget);
    expect(find.text('USD 840.50'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });
}
