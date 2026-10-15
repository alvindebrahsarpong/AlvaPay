import 'dart:convert';

import 'package:alvapay/backend_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryTokenStore implements SessionTokenStore {
  _MemoryTokenStore({this.token});

  String? token;
  String? email;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<String?> readAccountEmail() async => email;

  @override
  Future<void> writeAccountEmail(String value) async => email = value;

  @override
  Future<void> clear() async {
    token = null;
    email = null;
  }
}

void main() {
  test('registers, restores, and revokes an account session', () async {
    final tokenStore = _MemoryTokenStore();
    final requests = <http.Request>[];
    final api = AlvaPayApi(
      tokenStore: tokenStore,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/session') {
          return http.Response('{"token":"guest-session"}', 201);
        }
        if (request.url.path == '/api/auth/register') {
          expect(jsonDecode(request.body), {
            'email': 'user@example.test',
            'password': 'synthetic-test-passphrase',
          });
          expect(request.headers['Authorization'], 'Bearer guest-session');
          return http.Response(
            '{"token":"account-session","email":"user@example.test"}',
            201,
          );
        }
        expect(request.url.path, '/api/auth/logout');
        expect(request.headers['Authorization'], startsWith('Bearer '));
        return http.Response('{"status":"signed_out"}', 200);
      }),
      baseUri: Uri.parse('https://api.example.test'),
    );

    try {
      expect(await api.restoreAccount(), isNull);
      await api.register('user@example.test', 'synthetic-test-passphrase');
      expect(await api.restoreAccount(), 'user@example.test');
      expect(tokenStore.token, isNotNull);
      await api.logout();
      expect(tokenStore.token, isNull);
      expect(tokenStore.email, isNull);
      expect(requests.map((request) => request.url.path), [
        '/api/session',
        '/api/auth/register',
        '/api/auth/logout',
      ]);
    } finally {
      api.close();
    }
  });

  test('creates and reuses a session token before reading invoices', () async {
    final tokenStore = _MemoryTokenStore();
    final requests = <http.Request>[];
    final api = AlvaPayApi(
      tokenStore: tokenStore,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/session') {
          return http.Response('{"token":"private-session"}', 201);
        }
        return http.Response('[]', 200);
      }),
      baseUri: Uri.parse('https://api.example.test'),
    );

    try {
      expect(await api.listInvoices(), isEmpty);
      expect(tokenStore.token, 'private-session');
      expect(requests.first.method, 'POST');
      expect(requests.first.url.path, '/api/session');
      expect(requests.last.headers['Authorization'], 'Bearer private-session');
    } finally {
      api.close();
    }
  });

  test(
    'uses the USB-reversed backend address for Android by default',
    () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      late Uri requestUri;
      final api = AlvaPayApi(
        tokenStore: _MemoryTokenStore(token: 'private-session'),
        client: MockClient((request) async {
          requestUri = request.url;
          return http.Response('[]', 200);
        }),
      );

      try {
        expect(await api.listInvoices(), isEmpty);
        expect(requestUri, Uri.parse('http://127.0.0.1:8000/api/invoices'));
      } finally {
        api.close();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  test(
    'replaces an expired guest session and retries the request once',
    () async {
      final tokenStore = _MemoryTokenStore(token: 'expired-guest-session');
      final requests = <http.Request>[];
      var invoiceRequestCount = 0;
      final api = AlvaPayApi(
        tokenStore: tokenStore,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/invoices') {
            invoiceRequestCount++;
            if (invoiceRequestCount == 1) {
              return http.Response(
                '{"detail":"This AlvaPay session is no longer valid."}',
                401,
              );
            }
          }
          if (request.url.path == '/api/invoices' &&
              request.headers['Authorization'] ==
                  '****** expired-guest-session') {
            return http.Response(
              '{"detail":"This AlvaPay session is no longer valid."}',
              401,
            );
          }
          if (request.url.path == '/api/session') {
            return http.Response('{"token":"replacement-guest-session"}', 201);
          }
          return http.Response('[]', 200);
        }),
        baseUri: Uri.parse('https://api.example.test'),
      );

      try {
        expect(await api.listInvoices(), isEmpty);
        expect(tokenStore.token, 'replacement-guest-session');
        expect(requests.map((request) => request.url.path), [
          '/api/invoices',
          '/api/session',
          '/api/invoices',
        ]);
      } finally {
        api.close();
      }
    },
  );

  test('requests cash-flow summary over the authenticated API', () async {
    late http.Request sentRequest;
    final api = AlvaPayApi(
      tokenStore: _MemoryTokenStore(token: 'existing-session'),
      client: MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'verified_invoice_count': 2,
            'totals_by_currency': [
              {
                'currency': 'USD',
                'paid_invoice_count': 2,
                'received_cents': 16900,
              },
            ],
            'summary': 'Two verified USD payments are on record.',
          }),
          200,
        );
      }),
      baseUri: Uri.parse('https://api.example.test'),
    );

    try {
      final summary = await api.cashFlowSummary();
      expect(sentRequest.method, 'POST');
      expect(sentRequest.url.path, '/api/ai/cash-flow-summary');
      expect(sentRequest.headers['Authorization'], startsWith('Bearer '));
      expect(sentRequest.body, isEmpty);
      expect(summary.verifiedInvoiceCount, 2);
      expect(summary.totalsByCurrency.single.received, 'USD 169.00');
      expect(summary.summary, 'Two verified USD payments are on record.');
    } finally {
      api.close();
    }
  });

  test(
    'sends stable invoice idempotency and exact checkout confirmation',
    () async {
      final requests = <http.Request>[];
      final api = AlvaPayApi(
        tokenStore: _MemoryTokenStore(token: 'existing-session'),
        client: MockClient((request) async {
          requests.add(request);
          final data = request.body.isEmpty ? null : jsonDecode(request.body);
          if (request.url.path == '/api/invoices') {
            expect(
              request.headers['Idempotency-Key'],
              'invoice-create-key-0001',
            );
            expect(data['amount_cents'], 8450);
            return http.Response(jsonEncode(_invoiceJson()), 201);
          }
          if (request.url.path == '/api/invoices/invoice-1/checkout') {
            expect(data, {
              'confirmed': true,
              'amount_cents': 8450,
              'currency': 'USD',
            });
            return http.Response(
              jsonEncode({
                ..._invoiceJson(),
                'status': 'CHECKOUT_PENDING',
                'paypal_order_id': 'ORDER-1',
                'approval_url':
                    'https://www.sandbox.paypal.com/checkoutnow?token=ORDER-1',
              }),
              200,
            );
          }
          expect(request.url.path, '/api/invoices/invoice-1/capture');
          expect(request.body, isEmpty);
          return http.Response(
            jsonEncode({..._invoiceJson(), 'status': 'PAID'}),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      );
      final draft = InvoiceDraft(
        client: 'Ada Studio',
        customerEmail: 'billing@example.test',
        description: 'Brand identity',
        amountCents: 8450,
        dueDate: DateTime(2026, 10, 20),
        currency: 'USD',
      );

      try {
        final invoice = await api.createInvoice(
          draft,
          idempotencyKey: 'invoice-create-key-0001',
        );
        final pending = await api.createCheckout(invoice);
        final paid = await api.captureInvoice(pending);

        expect(
          requests.first.headers['Authorization'],
          'Bearer existing-session',
        );
        expect(pending.status, InvoiceStatus.awaiting);
        expect(pending.approvalUrl, contains('sandbox.paypal.com'));
        expect(paid.status, InvoiceStatus.paid);
      } finally {
        api.close();
      }
    },
  );

  test(
    'surfaces safe API error details without inventing a payment result',
    () async {
      final api = AlvaPayApi(
        tokenStore: _MemoryTokenStore(token: 'existing-session'),
        client: MockClient(
          (_) async => http.Response(
            '{"detail":"PayPal credentials are not configured."}',
            503,
          ),
        ),
        baseUri: Uri.parse('https://api.example.test'),
      );

      try {
        await expectLater(
          api.listInvoices(),
          throwsA(
            isA<AlvaPayApiException>().having(
              (error) => error.message,
              'message',
              'PayPal credentials are not configured.',
            ),
          ),
        );
      } finally {
        api.close();
      }
    },
  );
}

Map<String, Object?> _invoiceJson() => {
  'id': 'invoice-1',
  'customer_name': 'Ada Studio',
  'customer_email': 'billing@example.test',
  'service_description': 'Brand identity',
  'amount_cents': 8450,
  'currency': 'USD',
  'due_date': '2026-10-20',
  'status': 'DRAFT',
  'paypal_order_id': null,
  'approval_url': null,
  'paypal_capture_id': null,
  'created_at': '2026-10-17T12:00:00+00:00',
};
