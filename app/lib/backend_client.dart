import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

enum InvoiceStatus { draft, awaiting, processing, paid }

class Invoice {
  const Invoice({
    required this.id,
    required this.client,
    required this.customerEmail,
    required this.description,
    required this.amountCents,
    required this.dueDate,
    required this.status,
    required this.currency,
    required this.paypalOrderId,
    required this.approvalUrl,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'DRAFT' => InvoiceStatus.draft,
      'CHECKOUT_PENDING' => InvoiceStatus.awaiting,
      'ORDER_CREATING' || 'CAPTURE_IN_PROGRESS' => InvoiceStatus.processing,
      'PAID' => InvoiceStatus.paid,
      _ => throw const FormatException(
        'The API returned an unknown invoice status.',
      ),
    };
    final dueDateValue = json['due_date'];
    return Invoice(
      id: _requiredString(json, 'id'),
      client: _requiredString(json, 'customer_name'),
      customerEmail: _requiredString(json, 'customer_email'),
      description: _requiredString(json, 'service_description'),
      amountCents: _requiredInt(json, 'amount_cents'),
      dueDate: dueDateValue is String ? DateTime.tryParse(dueDateValue) : null,
      status: status,
      currency: _requiredString(json, 'currency'),
      paypalOrderId: json['paypal_order_id'] as String?,
      approvalUrl: json['approval_url'] as String?,
    );
  }

  final String id;
  final String client;
  final String customerEmail;
  final String description;
  final int amountCents;
  final DateTime? dueDate;
  final InvoiceStatus status;
  final String currency;
  final String? paypalOrderId;
  final String? approvalUrl;

  String get amount => '$currency ${(amountCents / 100).toStringAsFixed(2)}';
}

class InvoiceDraft {
  const InvoiceDraft({
    required this.client,
    required this.customerEmail,
    required this.description,
    required this.amountCents,
    required this.dueDate,
    required this.currency,
  });

  final String client;
  final String customerEmail;
  final String description;
  final int amountCents;
  final DateTime dueDate;
  final String currency;

  Map<String, Object?> toJson() => {
    'customer_name': client,
    'customer_email': customerEmail,
    'service_description': description,
    'amount_cents': amountCents,
    'currency': currency,
    'due_date':
        '${dueDate.year.toString().padLeft(4, '0')}-'
        '${dueDate.month.toString().padLeft(2, '0')}-'
        '${dueDate.day.toString().padLeft(2, '0')}',
  };
}

class CashFlowCurrencyTotal {
  const CashFlowCurrencyTotal({
    required this.currency,
    required this.paidInvoiceCount,
    required this.receivedCents,
  });

  factory CashFlowCurrencyTotal.fromJson(Map<String, dynamic> json) {
    return CashFlowCurrencyTotal(
      currency: _requiredString(json, 'currency'),
      paidInvoiceCount: _requiredInt(json, 'paid_invoice_count'),
      receivedCents: _requiredInt(json, 'received_cents'),
    );
  }

  final String currency;
  final int paidInvoiceCount;
  final int receivedCents;

  String get received =>
      '$currency ${(receivedCents / 100).toStringAsFixed(2)}';
}

class CashFlowSummary {
  const CashFlowSummary({
    required this.verifiedInvoiceCount,
    required this.totalsByCurrency,
    required this.summary,
  });

  factory CashFlowSummary.fromJson(Map<String, dynamic> json) {
    final totals = json['totals_by_currency'];
    if (totals is! List) {
      throw const FormatException('The API returned invalid cash-flow totals.');
    }
    return CashFlowSummary(
      verifiedInvoiceCount: _requiredInt(json, 'verified_invoice_count'),
      totalsByCurrency: totals
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException(
                'The API returned an invalid cash-flow total.',
              );
            }
            return CashFlowCurrencyTotal.fromJson(item);
          })
          .toList(growable: false),
      summary: _requiredString(json, 'summary'),
    );
  }

  final int verifiedInvoiceCount;
  final List<CashFlowCurrencyTotal> totalsByCurrency;
  final String summary;
}

abstract interface class AlvaPayBackend {
  Future<String?> restoreAccount();

  Future<void> register(String email, String password);

  Future<void> login(String email, String password);

  Future<void> logout();

  Future<List<Invoice>> listInvoices();

  Future<Map<String, dynamic>> analyzeInvoice(String text);

  Future<CashFlowSummary> cashFlowSummary();

  Future<Invoice> createInvoice(
    InvoiceDraft draft, {
    required String idempotencyKey,
  });

  Future<Invoice> createCheckout(Invoice invoice);

  Future<Invoice> captureInvoice(Invoice invoice);

  Future<Invoice> refreshInvoice(Invoice invoice);

  void close();
}

abstract interface class SessionTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<String?> readAccountEmail();

  Future<void> writeAccountEmail(String email);

  Future<void> clear();
}

class SecureSessionTokenStore implements SessionTokenStore {
  SecureSessionTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'alvapay.private-session-token';
  static const _accountEmailKey = 'alvapay.account-email';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<String?> readAccountEmail() => _storage.read(key: _accountEmailKey);

  @override
  Future<void> writeAccountEmail(String email) =>
      _storage.write(key: _accountEmailKey, value: email);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _accountEmailKey);
  }
}

class AlvaPayApiException implements Exception {
  const AlvaPayApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AlvaPayApi implements AlvaPayBackend {
  AlvaPayApi({http.Client? client, SessionTokenStore? tokenStore, Uri? baseUri})
    : _client = client ?? http.Client(),
      _tokenStore = tokenStore ?? SecureSessionTokenStore(),
      _baseUri = baseUri ?? _defaultBaseUri;

  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
  static final Uri _defaultBaseUri = Uri.parse(
    _configuredBaseUrl.isNotEmpty
        ? _configuredBaseUrl
        : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://127.0.0.1:8000'
        : 'http://localhost:8000',
  );

  final http.Client _client;
  final SessionTokenStore _tokenStore;
  final Uri _baseUri;
  String? _sessionToken;
  String? _accountEmail;

  @override
  Future<String?> restoreAccount() async {
    _sessionToken ??= await _tokenStore.read();
    if (_sessionToken == null || _sessionToken!.isEmpty) return null;
    _accountEmail = await _tokenStore.readAccountEmail();
    return _accountEmail;
  }

  @override
  Future<void> register(String email, String password) => _authenticate(
    '/api/auth/register',
    email,
    password,
    includeCurrentSession: true,
  );

  @override
  Future<void> login(String email, String password) => _authenticate(
    '/api/auth/login',
    email,
    password,
    includeCurrentSession: true,
  );

  Future<void> _authenticate(
    String path,
    String email,
    String password, {
    bool includeCurrentSession = false,
  }) async {
    final response = await _send(
      'POST',
      path,
      authenticated: includeCurrentSession,
      body: {'email': email, 'password': password},
    );
    if (response is! Map<String, dynamic> ||
        response['token'] is! String ||
        (response['token'] as String).isEmpty ||
        response['email'] is! String) {
      throw const FormatException('The API returned an invalid login session.');
    }

    final token = response['token'] as String;
    final accountEmail = response['email'] as String;
    await _tokenStore.clear();
    await _tokenStore.write(token);
    await _tokenStore.writeAccountEmail(accountEmail);
    _sessionToken = token;
    _accountEmail = accountEmail;
  }

  @override
  Future<void> logout() async {
    await _send('POST', '/api/auth/logout', authenticated: true);
    await _tokenStore.clear();
    _sessionToken = null;
    _accountEmail = null;
  }

  @override
  Future<List<Invoice>> listInvoices() async {
    final response = await _send('GET', '/api/invoices', authenticated: true);
    if (response is! List) {
      throw const FormatException('The API returned an invalid invoice list.');
    }
    return response
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('The API returned an invalid invoice.');
          }
          return Invoice.fromJson(item);
        })
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> analyzeInvoice(String text) async {
    final response = await _send(
      'POST',
      '/api/ai/draft',
      authenticated: true,
      body: {'text': text},
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException('The AI service returned an invalid draft.');
    }
    return response;
  }

  @override
  Future<CashFlowSummary> cashFlowSummary() async {
    final response = await _send(
      'POST',
      '/api/ai/cash-flow-summary',
      authenticated: true,
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException(
        'The AI service returned an invalid cash-flow summary.',
      );
    }
    return CashFlowSummary.fromJson(response);
  }

  @override
  Future<Invoice> createInvoice(
    InvoiceDraft draft, {
    required String idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      '/api/invoices',
      authenticated: true,
      body: draft.toJson(),
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return _invoice(response);
  }

  @override
  Future<Invoice> createCheckout(Invoice invoice) async {
    final response = await _send(
      'POST',
      '/api/invoices/${Uri.encodeComponent(invoice.id)}/checkout',
      authenticated: true,
      body: {
        'confirmed': true,
        'amount_cents': invoice.amountCents,
        'currency': invoice.currency,
      },
    );
    return _invoice(response);
  }

  @override
  Future<Invoice> captureInvoice(Invoice invoice) async {
    final response = await _send(
      'POST',
      '/api/invoices/${Uri.encodeComponent(invoice.id)}/capture',
      authenticated: true,
    );
    return _invoice(response);
  }

  @override
  Future<Invoice> refreshInvoice(Invoice invoice) async {
    final response = await _send(
      'POST',
      '/api/invoices/${Uri.encodeComponent(invoice.id)}/refresh',
      authenticated: true,
    );
    return _invoice(response);
  }

  @override
  void close() => _client.close();

  Future<dynamic> _send(
    String method,
    String path, {
    required bool authenticated,
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    final requestHeaders = <String, String>{'Accept': 'application/json'};
    if (body != null) requestHeaders['Content-Type'] = 'application/json';
    requestHeaders.addAll(headers);
    if (authenticated) {
      requestHeaders['Authorization'] = 'Bearer ${await _getSessionToken()}';
    }

    final request = http.Request(method, _baseUri.resolve(path))
      ..headers.addAll(requestHeaders);
    if (body != null) request.body = jsonEncode(body);

    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw AlvaPayApiException(
        detail is String
            ? detail
            : 'AlvaPay could not complete that request (${response.statusCode}).',
      );
    }
    return decoded;
  }

  Future<String> _getSessionToken() async {
    if (_sessionToken case final token?) return token;
    final saved = await _tokenStore.read();
    if (saved != null && saved.isNotEmpty) {
      _sessionToken = saved;
      return saved;
    }

    final response = await _send('POST', '/api/session', authenticated: false);
    if (response is! Map<String, dynamic> ||
        response['token'] is! String ||
        (response['token'] as String).isEmpty) {
      throw const FormatException(
        'The API did not create a valid private session.',
      );
    }
    final token = response['token'] as String;
    await _tokenStore.write(token);
    _sessionToken = token;
    return token;
  }

  static Invoice _invoice(dynamic response) {
    if (response is! Map<String, dynamic>) {
      throw const FormatException('The API returned an invalid invoice.');
    }
    return Invoice.fromJson(response);
  }
}

String newIdempotencyKey() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('The API invoice is missing $key.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('The API invoice is missing $key.');
  return value;
}
