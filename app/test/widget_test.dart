import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alvapay/backend_client.dart';
import 'package:alvapay/main.dart';

class _FakeBackend implements AlvaPayBackend {
  final List<Invoice> invoices = [];
  int creates = 0;
  int checkouts = 0;
  int captures = 0;

  @override
  Future<Map<String, dynamic>> analyzeInvoice(String text) async => {
    'customer_name': 'Morrow Studio',
    'customer_email': 'billing@morrow.example.test',
    'service_description': 'Brand identity',
    'amount_cents': 84050,
    'currency': 'USD',
    'due_date': '2026-10-20',
  };

  @override
  Future<Invoice> captureInvoice(Invoice invoice) async {
    captures++;
    final paid = _copy(invoice, status: InvoiceStatus.paid);
    _replace(paid);
    return paid;
  }

  @override
  Future<Invoice> createCheckout(Invoice invoice) async {
    checkouts++;
    final pending = _copy(
      invoice,
      status: InvoiceStatus.awaiting,
      paypalOrderId: 'ORDER-1',
      approvalUrl: 'https://www.sandbox.paypal.com/checkoutnow?token=ORDER-1',
    );
    _replace(pending);
    return pending;
  }

  @override
  Future<Invoice> createInvoice(
    InvoiceDraft draft, {
    required String idempotencyKey,
  }) async {
    creates++;
    final invoice = Invoice(
      id: 'invoice-$creates',
      client: draft.client,
      customerEmail: draft.customerEmail,
      description: draft.description,
      amountCents: draft.amountCents,
      dueDate: draft.dueDate,
      status: InvoiceStatus.draft,
      currency: draft.currency,
      paypalOrderId: null,
      approvalUrl: null,
    );
    invoices.insert(0, invoice);
    return invoice;
  }

  @override
  void close() {}

  @override
  Future<List<Invoice>> listInvoices() async => List.of(invoices);

  @override
  Future<Invoice> refreshInvoice(Invoice invoice) async => invoice;

  void _replace(Invoice updated) {
    final index = invoices.indexWhere((invoice) => invoice.id == updated.id);
    if (index >= 0) invoices[index] = updated;
  }

  Invoice _copy(
    Invoice invoice, {
    required InvoiceStatus status,
    String? paypalOrderId,
    String? approvalUrl,
  }) => Invoice(
    id: invoice.id,
    client: invoice.client,
    customerEmail: invoice.customerEmail,
    description: invoice.description,
    amountCents: invoice.amountCents,
    dueDate: invoice.dueDate,
    status: status,
    currency: invoice.currency,
    paypalOrderId: paypalOrderId ?? invoice.paypalOrderId,
    approvalUrl: approvalUrl ?? invoice.approvalUrl,
  );
}

void main() {
  testWidgets('dashboard fits a desktop workspace', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(AlvaPayApp(backend: _FakeBackend()));
    await tester.pumpAndSettle();

    expect(find.text('AlvaPay'), findsOneWidget);
    expect(find.text('New invoice'), findsOneWidget);
  });

  testWidgets('empty dashboard does not present fabricated payment records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(AlvaPayApp(backend: _FakeBackend()));
    await tester.pumpAndSettle();

    expect(find.text('AlvaPay'), findsOneWidget);
    expect(find.text('SANDBOX'), findsOneWidget);
    expect(find.text('No invoices yet'), findsOneWidget);
    expect(find.text('Juniper Coffee'), findsNothing);
  });

  testWidgets('AI draft can be reviewed, confirmed, opened, and verified', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = _FakeBackend();
    var launchedUrl = false;
    await tester.pumpWidget(
      AlvaPayApp(
        backend: backend,
        openApprovalUrl: (uri) async {
          launchedUrl = uri.host == 'www.sandbox.paypal.com';
          return launchedUrl;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create an invoice'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('invoice-natural-language')),
      'Brand identity for Morrow Studio, USD 840.50, due October 20.',
    );
    await tester.tap(find.text('Analyze with Alva AI'));
    await tester.pumpAndSettle();

    expect(find.text('Morrow Studio'), findsOneWidget);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('invoice-amount')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('invoice-amount')))
          .controller!
          .text,
      '840.50',
    );
    await tester.ensureVisible(find.text('Save reviewed draft'));
    await tester.tap(find.text('Save reviewed draft'));
    await tester.pumpAndSettle();

    expect(find.text('Morrow Studio'), findsOneWidget);
    expect(find.text('USD 840.50'), findsOneWidget);
    expect(find.text('Review & send request'), findsOneWidget);

    await tester.tap(find.text('Review & send request'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm this request'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('confirmation-amount'))).data,
      'USD 840.50',
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(backend.checkouts, 0);
    expect(find.text('Draft'), findsOneWidget);

    await tester.tap(find.text('Review & send request'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-checkout')));
    await tester.pumpAndSettle();

    expect(backend.checkouts, 1);
    expect(launchedUrl, isTrue);
    expect(find.text('Verify payment'), findsOneWidget);
    await tester.tap(find.text('Verify payment'));
    await tester.pumpAndSettle();

    expect(backend.captures, 1);
    expect(backend.invoices.single.status, InvoiceStatus.paid);
    expect(find.text('Paid'), findsNWidgets(2));
  });
}
