import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alvapay/backend_client.dart';
import 'package:alvapay/main.dart';

class _FakeBackend implements AlvaPayBackend {
  final List<Invoice> invoices = [];
  String? accountEmail;
  int creates = 0;
  int checkouts = 0;
  int captures = 0;
  int logins = 0;
  int registrations = 0;
  int logouts = 0;

  @override
  Future<String?> restoreAccount() async => accountEmail;

  @override
  Future<void> register(String email, String password) async {
    registrations++;
    accountEmail = email;
  }

  @override
  Future<void> login(String email, String password) async {
    logins++;
    accountEmail = email;
  }

  @override
  Future<void> logout() async {
    logouts++;
    accountEmail = null;
  }

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
  Future<CashFlowSummary> cashFlowSummary() async => const CashFlowSummary(
    verifiedInvoiceCount: 1,
    totalsByCurrency: [
      CashFlowCurrencyTotal(
        currency: 'USD',
        paidInvoiceCount: 1,
        receivedCents: 8450,
      ),
    ],
    summary: 'One verified USD payment is on record.',
  );

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
  double contrastRatio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

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

  testWidgets('dark theme keeps invoice text and payment status legible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = _FakeBackend();
    backend.invoices.add(
      Invoice(
        id: 'paid-invoice',
        client: 'Morrow Studio',
        customerEmail: 'billing@morrow.example.test',
        description: 'Brand identity',
        amountCents: 84050,
        dueDate: null,
        status: InvoiceStatus.paid,
        currency: 'USD',
        paypalOrderId: 'ORDER-1',
        approvalUrl: null,
      ),
    );
    backend.invoices.add(
      Invoice(
        id: 'awaiting-invoice',
        client: 'Juniper Coffee',
        customerEmail: 'billing@juniper.example.test',
        description: 'Campaign photography',
        amountCents: 12500,
        dueDate: null,
        status: InvoiceStatus.awaiting,
        currency: 'USD',
        paypalOrderId: 'ORDER-2',
        approvalUrl: 'https://www.sandbox.paypal.com/checkoutnow?token=ORDER-2',
      ),
    );
    await tester.pumpWidget(AlvaPayApp(backend: backend));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.text('Morrow Studio')));
    expect(theme.brightness, Brightness.dark);
    expect(
      contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface),
      greaterThanOrEqualTo(7),
    );
    expect(
      contrastRatio(
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.surface,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(theme.colorScheme.onPrimary, theme.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(
        theme.colorScheme.onPrimaryContainer,
        theme.colorScheme.primaryContainer,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(find.text('USD 840.50'), findsOneWidget);
    for (final statusKey in [
      const Key('invoice-status-paid-invoice'),
      const Key('invoice-status-awaiting-invoice'),
    ]) {
      final status = tester.widget<Text>(find.byKey(statusKey));
      expect(
        contrastRatio(status.style!.color!, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    }
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

    expect(find.text('A'), findsWidgets);
    expect(find.text('SANDBOX'), findsOneWidget);
    expect(find.text('No invoices yet'), findsOneWidget);
    expect(find.text('Juniper Coffee'), findsNothing);
  });

  testWidgets('assistant summarizes verified cash-flow records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(AlvaPayApp(backend: _FakeBackend()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alva AI'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Generate cash-flow summary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate cash-flow summary'));
    await tester.pumpAndSettle();

    expect(find.text('Verified cash flow'), findsOneWidget);
    expect(find.text('One verified USD payment is on record.'), findsOneWidget);
    expect(find.text('USD · 1 payment'), findsOneWidget);
    expect(find.text('USD 84.50'), findsOneWidget);
  });

  testWidgets('account dialog supports sign-in and sign-out', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = _FakeBackend();
    await tester.pumpWidget(AlvaPayApp(backend: backend));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign in or create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-email')),
      'user@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('account-password')),
      'synthetic-test-passphrase',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(backend.logins, 1);
    expect(find.byTooltip('user@example.test'), findsOneWidget);

    await tester.tap(find.byTooltip('user@example.test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(backend.logouts, 1);
    expect(find.byTooltip('Sign in or create an account'), findsOneWidget);
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
