import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backend_client.dart';

void main() {
  runApp(const AlvaPayApp());
}

const _ink = Color(0xFF182423);
const _muted = Color(0xFF74817D);
const _canvas = Color(0xFFF5F5F0);
const _paper = Color(0xFFFFFFFF);
const _line = Color(0xFFE6E9E3);
const _forest = Color(0xFF173B35);
const _mint = Color(0xFFD7E8D8);
const _gold = Color(0xFFE6C990);
const _darkCanvas = Color(0xFF0B1220);
const _darkSurface = Color(0xFF17211F);
const _darkElevated = Color(0xFF202C29);
const _darkText = Color(0xFFF7F3EA);
const _darkMuted = Color(0xFFBFC9D6);
const _darkLine = Color(0xFF39475A);
const _darkGold = Color(0xFFD8C17D);
const _darkGoldContainer = Color(0xFF3B3320);

extension _AlvaPayTheme on BuildContext {
  Color get appText => Theme.of(this).colorScheme.onSurface;
  Color get appMutedText => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get appBorder => Theme.of(this).colorScheme.outline;
  Color get appAccent => Theme.of(this).colorScheme.primary;
  Color get appOnAccent => Theme.of(this).colorScheme.onPrimary;
  Color get appAccentContainer => Theme.of(this).colorScheme.primaryContainer;
  Color get appOnAccentContainer =>
      Theme.of(this).colorScheme.onPrimaryContainer;
}

class AlvaPayApp extends StatefulWidget {
  const AlvaPayApp({super.key, this.backend, this.openApprovalUrl});

  final AlvaPayBackend? backend;
  final Future<bool> Function(Uri uri)? openApprovalUrl;

  @override
  State<AlvaPayApp> createState() => _AlvaPayAppState();
}

class _AlvaPayAppState extends State<AlvaPayApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final AlvaPayBackend _backend;
  late final bool _ownsBackend;
  ThemeMode _themeMode = ThemeMode.light;
  int _selectedIndex = 0;
  String? _accountEmail;
  List<Invoice> _invoices = [];
  final Set<String> _busyInvoices = {};
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _ownsBackend = widget.backend == null;
    _backend = widget.backend ?? AlvaPayApi();
    unawaited(_restoreAccount());
    unawaited(_reloadInvoices());
  }

  @override
  void dispose() {
    if (_ownsBackend) _backend.close();
    super.dispose();
  }

  Future<void> _reloadInvoices() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final invoices = await _backend.listInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() {
        _loadError = message;
        _loading = false;
      });
      if (_invoices.isNotEmpty) _showMessage(message);
    }
  }

  Future<void> _restoreAccount() async {
    try {
      final email = await _backend.restoreAccount();
      if (mounted) setState(() => _accountEmail = email);
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    }
  }

  void _showMessage(String message) {
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _replaceInvoice(Invoice updated) {
    setState(() {
      _invoices = [
        for (final invoice in _invoices)
          if (invoice.id == updated.id) updated else invoice,
      ];
    });
  }

  Future<void> _runInvoiceAction(
    Invoice invoice,
    Future<Invoice> Function() action, {
    required String successMessage,
  }) async {
    if (_busyInvoices.contains(invoice.id)) return;
    setState(() => _busyInvoices.add(invoice.id));
    try {
      final updated = await action();
      if (!mounted) return;
      _replaceInvoice(updated);
      _showMessage(successMessage);
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _busyInvoices.remove(invoice.id));
    }
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  void _showAccountDialog() {
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) return;
    showDialog<void>(
      context: dialogContext,
      builder: (context) => AccountDialog(
        accountEmail: _accountEmail,
        onLogin: _loginAccount,
        onRegister: _registerAccount,
        onLogout: _logoutAccount,
      ),
    );
  }

  Future<void> _loginAccount(String email, String password) async {
    await _backend.login(email, password);
    final accountEmail = await _backend.restoreAccount();
    if (!mounted) return;
    setState(() {
      _accountEmail = accountEmail;
      _invoices = [];
    });
    await _reloadInvoices();
  }

  Future<void> _registerAccount(String email, String password) async {
    await _backend.register(email, password);
    final accountEmail = await _backend.restoreAccount();
    if (!mounted) return;
    setState(() {
      _accountEmail = accountEmail;
      _invoices = [];
    });
    await _reloadInvoices();
  }

  Future<void> _logoutAccount() async {
    await _backend.logout();
    if (!mounted) return;
    setState(() {
      _accountEmail = null;
      _invoices = [];
    });
    await _reloadInvoices();
  }

  Future<void> _openComposer() async {
    final sheetContext = _navigatorKey.currentContext;
    if (sheetContext == null) return;
    final invoice = await showModalBottomSheet<Invoice>(
      context: sheetContext,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => InvoiceComposer(
        analyzeInvoice: _backend.analyzeInvoice,
        saveInvoice: (draft, key) =>
            _backend.createInvoice(draft, idempotencyKey: key),
      ),
    );
    if (invoice == null || !mounted) return;
    setState(() {
      _invoices = [invoice, ..._invoices];
      _selectedIndex = 1;
    });
    _showMessage('Draft saved. Review the exact total before checkout.');
  }

  Future<void> _reviewAndCheckout(Invoice invoice) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CheckoutConfirmationSheet(invoice: invoice),
    );
    if (confirmed != true || !mounted) return;
    await _runInvoiceAction(
      invoice,
      () async {
        final pending = await _backend.createCheckout(invoice);
        _replaceInvoice(pending);
        final rawUrl = pending.approvalUrl;
        final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
        if (uri == null || !_isSandboxApprovalUrl(uri)) {
          throw const FormatException(
            'AlvaPay did not return a valid Sandbox approval link.',
          );
        }
        final opened = await (widget.openApprovalUrl ?? _openExternalUrl)(uri);
        if (!opened) {
          throw const AlvaPayApiException(
            'The Sandbox checkout is ready, but this device could not open it. '
            'Try opening PayPal again from the invoice.',
          );
        }
        return pending;
      },
      successMessage: 'PayPal Sandbox opened. Return here after approval to verify payment.',
    );
  }

  bool _isSandboxApprovalUrl(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'www.sandbox.paypal.com' ||
          uri.host == 'sandbox.paypal.com');

  Future<bool> _openExternalUrl(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _openApprovalUrl(Invoice invoice) async {
    final rawUrl = invoice.approvalUrl;
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (uri == null || !_isSandboxApprovalUrl(uri)) {
      _showMessage('A valid Sandbox approval link is not available.');
      return;
    }
    try {
      final opened = await (widget.openApprovalUrl ?? _openExternalUrl)(uri);
      if (!opened) _showMessage('Could not open PayPal Sandbox. Try again.');
    } catch (error) {
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _verifyPayment(Invoice invoice) => _runInvoiceAction(
    invoice,
    () => _backend.captureInvoice(invoice),
    successMessage: 'PayPal verified this payment.',
  );

  Future<void> _refreshInvoice(Invoice invoice) => _runInvoiceAction(
    invoice,
    () => _backend.refreshInvoice(invoice),
    successMessage: 'Invoice status refreshed from PayPal.',
  );

  bool _isInvoiceBusy(Invoice invoice) => _busyInvoices.contains(invoice.id);

  Widget _startupState() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading invoices'),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 38,
              color: context.appMutedText,
            ),
            const SizedBox(height: 14),
            const Text(
              'Your workspace is waiting',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? 'Connect to the AlvaPay backend to load invoices.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appMutedText),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _reloadInvoices,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry connection'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeMode == ThemeMode.dark;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _forest,
          brightness: isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          surface: isDark ? _darkSurface : _paper,
          onSurface: isDark ? _darkText : _ink,
          onSurfaceVariant: isDark ? _darkMuted : _muted,
          primary: isDark ? _darkGold : _forest,
          onPrimary: isDark ? _darkCanvas : Colors.white,
          primaryContainer: isDark ? _darkGoldContainer : _mint,
          onPrimaryContainer: isDark ? const Color(0xFFFFE6A8) : _forest,
          outline: isDark ? _darkLine : _line,
          surfaceContainerLow: isDark ? const Color(0xFF121B29) : _canvas,
          surfaceContainerHighest: isDark ? _darkElevated : _canvas,
        );
    final theme = ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: isDark ? _darkCanvas : _canvas,
      colorScheme: colorScheme,
      textTheme:
          ThemeData(brightness: isDark ? Brightness.dark : Brightness.light)
              .textTheme
              .apply(
                bodyColor: colorScheme.onSurface,
                displayColor: colorScheme.onSurface,
              ),
      dividerColor: colorScheme.outline,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? _darkElevated : _canvas,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outline),
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outline),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );

    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'AlvaPay',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: _themeMode,
      home: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              return Row(
                children: [
                  if (isWide) _desktopNavigation(),
                  Expanded(
                    child: Column(
                      children: [
                        _topBar(isWide),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1160),
                              child:
                                  _invoices.isEmpty &&
                                      (_loading || _loadError != null)
                                  ? _startupState()
                                  : _currentPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
            ? NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_rounded),
                    label: 'Overview',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    label: 'Invoices',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    label: 'Alva AI',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _topBar(bool isWide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 20, 14, isWide ? 36 : 20, 10),
      child: Row(
        children: [
          if (!isWide) const _BrandMonogram(),
          if (!isWide) const Spacer(),
          const _SandboxPill(),
          SizedBox(width: isWide ? 12 : 4),
          if (isWide)
            IconButton(
              tooltip: 'Refresh invoice records',
              onPressed: _loading ? null : _reloadInvoices,
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            tooltip: _accountEmail ?? 'Sign in or create an account',
            onPressed: _showAccountDialog,
            icon: Icon(
              _accountEmail == null
                  ? Icons.person_outline_rounded
                  : Icons.account_circle_outlined,
            ),
          ),
          IconButton(
            tooltip: _themeMode == ThemeMode.light
                ? 'Switch to dark theme'
                : 'Switch to light theme',
            onPressed: _toggleTheme,
            icon: Icon(
              _themeMode == ThemeMode.light
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopNavigation() {
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: context.appBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(),
          const SizedBox(height: 50),
          const _Eyebrow('WORKSPACE'),
          const SizedBox(height: 12),
          _navItem(0, Icons.grid_view_rounded, 'Overview'),
          _navItem(1, Icons.receipt_long_outlined, 'Invoices'),
          _navItem(2, Icons.auto_awesome_outlined, 'Alva AI'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.appBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: context.appAccent, size: 20),
                const SizedBox(height: 12),
                const Text(
                  'A little more peace of mind.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                Text(
                  'Checkout stays in the sandbox until you are ready.',
                  style: TextStyle(
                    color: context.appMutedText,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'ALVAPAY  ·  SANDBOX',
            style: TextStyle(color: context.appMutedText, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = index == _selectedIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? context.appAccentContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = index),
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? context.appOnAccentContainer
                      : context.appMutedText,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? context.appOnAccentContainer
                        : context.appMutedText,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _currentPage() {
    return switch (_selectedIndex) {
      1 => InvoiceList(
        invoices: _invoices,
        onCreateInvoice: _openComposer,
        onReviewInvoice: _reviewAndCheckout,
        onOpenCheckout: _openApprovalUrl,
        onVerifyInvoice: _verifyPayment,
        onRefreshInvoice: _refreshInvoice,
        isBusy: _isInvoiceBusy,
        onRefresh: _reloadInvoices,
      ),
      2 => AssistantPage(
        onCreateInvoice: _openComposer,
        loadCashFlowSummary: _backend.cashFlowSummary,
      ),
      _ => DashboardPage(
        invoices: _invoices,
        onCreateInvoice: _openComposer,
        onOpenInvoices: () => setState(() => _selectedIndex = 1),
        onOpenAssistant: () => setState(() => _selectedIndex = 2),
      ),
    };
  }
}

class AccountDialog extends StatefulWidget {
  const AccountDialog({
    required this.accountEmail,
    required this.onLogin,
    required this.onRegister,
    required this.onLogout,
    super.key,
  });

  final String? accountEmail;
  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function(String email, String password) onRegister;
  final Future<void> Function() onLogout;

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  bool _creatingAccount = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.accountEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;
      if (_creatingAccount) {
        await widget.onRegister(email, password);
      } else {
        await widget.onLogin(email, password);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onLogout();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.accountEmail case final email?) {
      return AlertDialog(
        title: const Text('Your AlvaPay account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Your invoices are private to this account.',
              style: TextStyle(height: 1.5),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _signOut,
            child: const Text('Sign out'),
          ),
          FilledButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_creatingAccount ? 'Create your account' : 'Welcome back'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _creatingAccount
                      ? 'Create a private workspace for your invoices.'
                      : 'Sign in to your private invoice workspace.',
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('account-email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                        ? null
                        : 'Enter a valid email address.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('account-password'),
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  validator: (value) {
                    if ((value ?? '').length < 12) {
                      return 'Use at least 12 characters.';
                    }
                    return null;
                  },
                ),
                if (_creatingAccount) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Use at least 12 characters. Password recovery is not '
                    'available in this MVP.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error, style: TextStyle(color: colorScheme.error)),
                ],
                const SizedBox(height: 16),
                if (_submitting)
                  const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Signing in',
                    ),
                  )
                else
                  FilledButton(
                    onPressed: _submit,
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
                    ),
                    child: Text(
                      _creatingAccount ? 'Create account' : 'Sign in',
                    ),
                  ),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() {
                          _creatingAccount = !_creatingAccount;
                          _error = null;
                        }),
                  child: Text(
                    _creatingAccount
                        ? 'Already have an account? Sign in'
                        : 'New to AlvaPay? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

String _friendlyError(Object error) {
  if (error is AlvaPayApiException) return error.message;
  if (error is TimeoutException) {
    return 'The request took too long. Check your connection and try again.';
  }
  if (error is FormatException) {
    return 'AlvaPay received an invalid response. Refresh and try again.';
  }
  return 'AlvaPay could not reach the backend. Check its URL and try again.';
}

Map<String, int> _totalsByCurrency(Iterable<Invoice> invoices) {
  final totals = <String, int>{};
  for (final invoice in invoices) {
    totals.update(
      invoice.currency,
      (total) => total + invoice.amountCents,
      ifAbsent: () => invoice.amountCents,
    );
  }
  return totals;
}

String _currentDateLabel() {
  const months = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  final today = DateTime.now();
  return '${months[today.month - 1]} ${today.day}';
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.invoices,
    required this.onCreateInvoice,
    required this.onOpenInvoices,
    required this.onOpenAssistant,
    super.key,
  });

  final List<Invoice> invoices;
  final VoidCallback onCreateInvoice;
  final VoidCallback onOpenInvoices;
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;
    final awaiting = _totalsByCurrency(
      invoices.where(
        (invoice) =>
            invoice.status == InvoiceStatus.awaiting ||
            invoice.status == InvoiceStatus.processing,
      ),
    );
    final collected = _totalsByCurrency(
      invoices.where((invoice) => invoice.status == InvoiceStatus.paid),
    );
    final recent = invoices.take(3).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(isWide ? 38 : 20, 18, isWide ? 38 : 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Eyebrow(_currentDateLabel()),
                    SizedBox(height: 9),
                    Text(
                      'Make room for\nyour next big thing.',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 38,
                        height: 1.06,
                        letterSpacing: -1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isWide)
                FilledButton.icon(
                  onPressed: onCreateInvoice,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New invoice'),
                  style: _primaryButtonStyle(context),
                ),
            ],
          ),
          if (!isWide) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCreateInvoice,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create an invoice'),
                style: _primaryButtonStyle(context),
              ),
            ),
          ],
          const SizedBox(height: 26),
          _MomentumCard(
            awaitingTotals: awaiting,
            collectedTotals: collected,
            onOpenAssistant: onOpenAssistant,
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final metricWidth =
                  (constraints.maxWidth - (isWide ? 32 : 16)) /
                  (isWide ? 3 : 2);
              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: metricWidth,
                    child: _MetricCard(
                      icon: Icons.hourglass_top_rounded,
                      label: 'In progress',
                      value:
                          '${invoices.where((i) => i.status == InvoiceStatus.awaiting || i.status == InvoiceStatus.processing).length}',
                      caption: 'Awaiting payment',
                      accent: const Color(0xFFF7EBD3),
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _MetricCard(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Completed',
                      value:
                          '${invoices.where((i) => i.status == InvoiceStatus.paid).length}',
                      caption: 'Successfully settled',
                      accent: const Color(0xFFE2EEE3),
                    ),
                  ),
                  if (isWide)
                    SizedBox(
                      width: metricWidth,
                      child: _MetricCard(
                        icon: Icons.edit_note_rounded,
                        label: 'In the wings',
                        value:
                            '${invoices.where((i) => i.status == InvoiceStatus.draft).length}',
                        caption: 'Draft invoices',
                        accent: const Color(0xFFE9E8F2),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent activity',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpenInvoices,
                child: const Text('All invoices'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ActivityCard(invoices: recent),
          const SizedBox(height: 16),
          Text(
            'Payment states update only after server verification.',
            style: TextStyle(fontSize: 11, color: context.appMutedText),
          ),
        ],
      ),
    );
  }
}

class _MomentumCard extends StatelessWidget {
  const _MomentumCard({
    required this.awaitingTotals,
    required this.collectedTotals,
    required this.onOpenAssistant,
  });

  final Map<String, int> awaitingTotals;
  final Map<String, int> collectedTotals;
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;
    final cardBackground = Theme.of(context).brightness == Brightness.dark
        ? context.appAccentContainer
        : _forest;
    final cardForeground = Theme.of(context).brightness == Brightness.dark
        ? context.appOnAccentContainer
        : Colors.white;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _BrandMonogram(),
            const SizedBox(width: 10),
            Text(
              'YOUR MOMENTUM',
              style: TextStyle(
                color: cardForeground.withValues(alpha: 0.78),
                fontSize: 10,
                letterSpacing: 1.8,
              ),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 26),
        if (awaitingTotals.isEmpty)
          Text(
            'No open invoices',
            style: TextStyle(
              color: cardForeground,
              fontSize: 27,
              height: 1.1,
              letterSpacing: -0.8,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          for (var index = 0; index < awaitingTotals.length; index++)
            Text(
              _money(
                awaitingTotals.values.elementAt(index),
                awaitingTotals.keys.elementAt(index),
              ),
              style: TextStyle(
                color: cardForeground,
                fontSize: index == 0 ? 34 : 18,
                height: 1.1,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        const SizedBox(height: 8),
        Text(
          awaitingTotals.isEmpty
              ? 'Your verified records, in one place'
              : 'Still on its way to you',
          style: TextStyle(
            color: cardForeground.withValues(alpha: 0.82),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 23),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
        const SizedBox(height: 15),
        Row(
          children: [
            const Icon(Icons.south_west_rounded, color: _gold, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                collectedTotals.isEmpty
                    ? 'Nothing collected yet'
                    : '${collectedTotals.entries.map((entry) => _money(entry.value, entry.key)).join(' · ')} collected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ask Alva',
              onPressed: onOpenAssistant,
              icon: const Icon(Icons.auto_awesome, size: 18),
              color: _gold,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 27 : 21),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: cardBackground.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: isWide
          ? Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 24),
                const SizedBox(
                  width: 210,
                  height: 150,
                  child: _MomentumOrbit(),
                ),
              ],
            )
          : content,
    );
  }
}

class _MomentumOrbit extends StatelessWidget {
  const _MomentumOrbit();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OrbitPainter(),
      child: const Center(
        child: Icon(Icons.arrow_outward_rounded, color: _gold, size: 24),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final inset in [6.0, 23.0, 41.0]) {
      canvas.drawCircle(center, (size.shortestSide / 2) - inset, stroke);
    }
    final arc = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.shortestSide / 2 - 23),
      -1.9,
      1.45,
      false,
      arc,
    );
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.3),
      3,
      Paint()..color = _gold,
    );
    canvas.drawCircle(
      Offset(size.width * 0.27, size.height * 0.68),
      2,
      Paint()..color = _mint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minWidth: 145),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: isDark ? context.appAccentContainer : accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: isDark ? context.appOnAccentContainer : _forest,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11, color: context.appMutedText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            value,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            caption,
            style: TextStyle(fontSize: 11, color: context.appMutedText),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.invoices,
    this.showActions = false,
    this.onReviewInvoice,
    this.onOpenCheckout,
    this.onVerifyInvoice,
    this.onRefreshInvoice,
    this.isBusy,
  });

  final List<Invoice> invoices;
  final bool showActions;
  final ValueChanged<Invoice>? onReviewInvoice;
  final ValueChanged<Invoice>? onOpenCheckout;
  final ValueChanged<Invoice>? onVerifyInvoice;
  final ValueChanged<Invoice>? onRefreshInvoice;
  final bool Function(Invoice)? isBusy;

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No invoices yet',
        message: 'Describe your work and Alva will help shape a first draft.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var index = 0; index < invoices.length; index++) ...[
            _InvoiceRow(
              invoice: invoices[index],
              showActions: showActions,
              onReview: onReviewInvoice,
              onOpenCheckout: onOpenCheckout,
              onVerify: onVerifyInvoice,
              onRefresh: onRefreshInvoice,
              isBusy: isBusy?.call(invoices[index]) ?? false,
            ),
            if (index != invoices.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, color: context.appBorder),
              ),
          ],
        ],
      ),
    );
  }
}

class InvoiceList extends StatefulWidget {
  const InvoiceList({
    required this.invoices,
    required this.onCreateInvoice,
    required this.onReviewInvoice,
    required this.onOpenCheckout,
    required this.onVerifyInvoice,
    required this.onRefreshInvoice,
    required this.isBusy,
    required this.onRefresh,
    super.key,
  });

  final List<Invoice> invoices;
  final VoidCallback onCreateInvoice;
  final ValueChanged<Invoice> onReviewInvoice;
  final ValueChanged<Invoice> onOpenCheckout;
  final ValueChanged<Invoice> onVerifyInvoice;
  final ValueChanged<Invoice> onRefreshInvoice;
  final bool Function(Invoice) isBusy;
  final Future<void> Function() onRefresh;

  @override
  State<InvoiceList> createState() => _InvoiceListState();
}

class _InvoiceListState extends State<InvoiceList> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.invoices.where((invoice) {
      return switch (_filter) {
        'Awaiting' =>
          invoice.status == InvoiceStatus.awaiting ||
              invoice.status == InvoiceStatus.processing,
        'Paid' => invoice.status == InvoiceStatus.paid,
        'Drafts' => invoice.status == InvoiceStatus.draft,
        _ => true,
      };
    }).toList();
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow('YOUR CLIENT WORK'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Invoices',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 36,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.onCreateInvoice,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New'),
                  style: _primaryButtonStyle(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Every detail, in one thoughtful place.',
              style: TextStyle(color: context.appMutedText),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              children: [
                for (final filter in ['All', 'Awaiting', 'Paid', 'Drafts'])
                  ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                    selectedColor: context.appAccentContainer,
                    side: BorderSide(
                      color: _filter == filter
                          ? context.appAccentContainer
                          : context.appBorder,
                    ),
                    labelStyle: TextStyle(
                      color: _filter == filter
                          ? context.appOnAccentContainer
                          : context.appMutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              _EmptyState(
                icon: widget.invoices.isEmpty
                    ? Icons.receipt_long_outlined
                    : Icons.filter_list_off_rounded,
                title: widget.invoices.isEmpty
                    ? 'No invoices yet'
                    : 'No matching invoices',
                message: widget.invoices.isEmpty
                    ? 'Describe your work and Alva will help shape a first draft.'
                    : 'Try another filter or start a fresh draft.',
              )
            else
              _ActivityCard(
                invoices: filtered,
                showActions: true,
                onReviewInvoice: widget.onReviewInvoice,
                onOpenCheckout: widget.onOpenCheckout,
                onVerifyInvoice: widget.onVerifyInvoice,
                onRefreshInvoice: widget.onRefreshInvoice,
                isBusy: widget.isBusy,
              ),
            const SizedBox(height: 14),
            Text(
              'Payment status is confirmed by the AlvaPay backend, never by a redirect.',
              style: TextStyle(fontSize: 11, color: context.appMutedText),
            ),
          ],
        ),
      ),
    );
  }
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    required this.onCreateInvoice,
    required this.loadCashFlowSummary,
    super.key,
  });

  final VoidCallback onCreateInvoice;
  final Future<CashFlowSummary> Function() loadCashFlowSummary;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  CashFlowSummary? _summary;
  String? _summaryError;
  bool _loadingSummary = false;

  Future<void> _generateSummary() async {
    setState(() {
      _loadingSummary = true;
      _summaryError = null;
    });
    try {
      final summary = await widget.loadCashFlowSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loadingSummary = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _summaryError = _friendlyError(error);
        _loadingSummary = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 38 : 24, 28, wide ? 38 : 24, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('ALVAPAY AI'),
          const SizedBox(height: 8),
          const Text(
            'A clearer first draft.',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 36,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Describe the work in your own words. Alva turns it into an editable invoice draft; nothing is saved or sent until you review it.',
            style: TextStyle(color: context.appMutedText, height: 1.55),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: context.appBorder),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BrandMonogram(),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'AI can suggest the client, service, amount, currency, and due date. You remain in control of every field and every payment.',
                    style: TextStyle(height: 1.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: widget.onCreateInvoice,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Draft an invoice with AI'),
            style: _primaryButtonStyle(context),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: context.appBorder),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verified cash flow',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Alva summarizes only payments verified by PayPal. '
                  'Pending and unpaid invoices are excluded.',
                  style: TextStyle(color: context.appMutedText, height: 1.5),
                ),
                const SizedBox(height: 16),
                if (_summary case final summary?) ...[
                  Text(summary.summary, style: const TextStyle(height: 1.5)),
                  if (summary.totalsByCurrency.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    for (final total in summary.totalsByCurrency)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${total.currency} · ${total.paidInvoiceCount} '
                                '${total.paidInvoiceCount == 1 ? 'payment' : 'payments'}',
                                style: TextStyle(color: context.appMutedText),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              total.received,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
                if (_summaryError case final error?) ...[
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_loadingSummary)
                  const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Generating verified cash-flow summary',
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _generateSummary,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      _summaryError == null
                          ? 'Generate cash-flow summary'
                          : 'Try again',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: context.appAccent,
                      side: BorderSide(color: context.appBorder),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InvoiceComposer extends StatefulWidget {
  const InvoiceComposer({
    required this.analyzeInvoice,
    required this.saveInvoice,
    super.key,
  });

  final Future<Map<String, dynamic>> Function(String text) analyzeInvoice;
  final Future<Invoice> Function(InvoiceDraft draft, String idempotencyKey)
  saveInvoice;

  @override
  State<InvoiceComposer> createState() => _InvoiceComposerState();
}

class _InvoiceComposerState extends State<InvoiceComposer> {
  final _formKey = GlobalKey<FormState>();
  final _client = TextEditingController();
  final _email = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _brief = TextEditingController();
  final _saveKey = newIdempotencyKey();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 14));
  String _currency = 'USD';
  bool _analyzing = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _client.dispose();
    _email.dispose();
    _description.dispose();
    _amount.dispose();
    _brief.dispose();
    super.dispose();
  }

  int? _parseAmount(String value) {
    final match = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$')
        .firstMatch(value.trim());
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return whole * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  }

  Future<void> _analyzeBrief() async {
    final text = _brief.text.trim();
    if (text.length < 8 || _analyzing) {
      setState(() => _error = 'Add a short description of the invoice first.');
      return;
    }
    setState(() {
      _analyzing = true;
      _error = null;
    });
    try {
      final draft = await widget.analyzeInvoice(text);
      if (!mounted) return;
      final customerName = draft['customer_name'];
      final customerEmail = draft['customer_email'];
      final description = draft['service_description'];
      final amountCents = draft['amount_cents'];
      final currency = draft['currency'];
      final dueDate = draft['due_date'];
      if (customerName is String) _client.text = customerName;
      if (customerEmail is String) _email.text = customerEmail;
      if (description is String) _description.text = description;
      if (amountCents is int) {
        _amount.text = (amountCents / 100).toStringAsFixed(2);
      }
      if (currency is String &&
          const {'USD', 'EUR', 'GBP', 'CAD'}.contains(currency)) {
        _currency = currency;
      }
      final parsedDate = dueDate is String ? DateTime.tryParse(dueDate) : null;
      if (parsedDate != null) _dueDate = parsedDate;
      setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AlvaPayApiException ? error.message : 'Alva could not analyze that brief. Check the connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = InvoiceDraft(
      client: _client.text.trim(),
      customerEmail: _email.text.trim(),
      description: _description.text.trim(),
      amountCents: _parseAmount(_amount.text)!,
      dueDate: _dueDate,
      currency: _currency,
    );
    try {
      final invoice = await widget.saveInvoice(draft, _saveKey);
      if (mounted) Navigator.of(context).pop(invoice);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AlvaPayApiException ? error.message : 'The draft could not be saved. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            22,
            14,
            22,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.appBorder,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const _Eyebrow('A FRESH START'),
                const SizedBox(height: 7),
                const Text(
                  'Create an invoice',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 31,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Shape the details. Your client never sees a thing until you say so.',
                  style: TextStyle(color: context.appMutedText, height: 1.4),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border.all(color: context.appBorder),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Eyebrow('START WITH A SENTENCE'),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('invoice-natural-language'),
                        controller: _brief,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Brand identity for Morrow Studio, USD 840.50, due October 20',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SuggestionChip(
                            label: 'Brand identity · USD 840.50',
                            onTap: () {
                              _brief.text =
                                  'Brand identity project for Morrow Studio, '
                                  'USD 840.50, due October 20, 2026.';
                            },
                          ),
                          _SuggestionChip(
                            label: 'Product photography · EUR 1,250',
                            onTap: () {
                              _brief.text =
                                  'Product photography for Juniper Coffee, '
                                  'EUR 1,250, due November 3, 2026.';
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _analyzing ? null : _analyzeBrief,
                        icon: _analyzing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_outlined),
                        label: Text(
                          _analyzing
                              ? 'Reading your brief…'
                              : 'Analyze with Alva AI',
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _InlineError(message: _error!),
                ],
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('invoice-client-name'),
                  controller: _client,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Client name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Add a client name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('invoice-client-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Client email'),
                  validator: (value) {
                    if (value == null ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value.trim())) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('invoice-description'),
                  controller: _description,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'What did you make together?',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Add a service description'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        key: const Key('invoice-amount'),
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          hintText: '0.00',
                        ),
                        validator: (value) {
                          final amount = value == null
                              ? null
                              : _parseAmount(value);
                          return amount == null || amount <= 0
                              ? 'Enter a valid amount'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                          DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                          DropdownMenuItem(value: 'CAD', child: Text('CAD')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _currency = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _dueDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) setState(() => _dueDate = date);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Due ${_formatDate(_dueDate)}'),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: context.appText,
                    side: BorderSide(color: context.appBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border.all(color: context.appBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 18,
                        color: context.appAccent,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Review every field above. Saving creates a private draft only; PayPal is not contacted until you confirm the exact total.',
                          style: TextStyle(fontSize: 12, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: _primaryButtonStyle(context),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save reviewed draft'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CheckoutConfirmationSheet extends StatelessWidget {
  const CheckoutConfirmationSheet({required this.invoice, super.key});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        26,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('FINAL REVIEW'),
          const SizedBox(height: 8),
          const Text(
            'Confirm this request',
            style: TextStyle(fontFamily: 'serif', fontSize: 30),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border.all(color: context.appBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.client,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  invoice.customerEmail,
                  style: TextStyle(color: context.appMutedText),
                ),
                const SizedBox(height: 18),
                Text(
                  invoice.amount,
                  key: const Key('confirmation-amount'),
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  invoice.description,
                  style: TextStyle(color: context.appMutedText),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'You’ll continue to PayPal Sandbox to approve this payment. AlvaPay will not mark it paid unless the backend verifies the completed order.',
            style: TextStyle(
              color: context.appMutedText,
              height: 1.45,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const Key('confirm-checkout'),
                  onPressed: () => Navigator.of(context).pop(true),
                  style: _primaryButtonStyle(context),
                  child: const Text('Confirm & continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.08),
        border: Border.all(color: errorColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: errorColor, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: errorColor, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.showActions,
    required this.onReview,
    required this.onOpenCheckout,
    required this.onVerify,
    required this.onRefresh,
    required this.isBusy,
  });

  final Invoice invoice;
  final bool showActions;
  final ValueChanged<Invoice>? onReview;
  final ValueChanged<Invoice>? onOpenCheckout;
  final ValueChanged<Invoice>? onVerify;
  final ValueChanged<Invoice>? onRefresh;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = switch (invoice.status) {
      InvoiceStatus.paid =>
        isDark ? const Color(0xFF81C995) : const Color(0xFF347359),
      InvoiceStatus.awaiting =>
        isDark ? const Color(0xFFE4BE68) : const Color(0xFF9B6B19),
      InvoiceStatus.processing =>
        isDark ? const Color(0xFF98BCD8) : const Color(0xFF54718A),
      InvoiceStatus.draft => context.appMutedText,
    };
    final statusText = switch (invoice.status) {
      InvoiceStatus.paid => 'Paid',
      InvoiceStatus.awaiting => 'Awaiting',
      InvoiceStatus.processing => 'Processing',
      InvoiceStatus.draft => 'Draft',
    };
    final statusIcon = switch (invoice.status) {
      InvoiceStatus.paid => Icons.check_circle_outline_rounded,
      InvoiceStatus.awaiting => Icons.schedule_rounded,
      InvoiceStatus.processing => Icons.sync_rounded,
      InvoiceStatus.draft => Icons.edit_note_rounded,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 19,
                  color: context.appAccent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.client,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${invoice.description}'
                      '${invoice.dueDate == null ? '' : '  ·  Due ${_formatDate(invoice.dueDate!)}'}',
                      style: TextStyle(
                        color: context.appMutedText,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    invoice.amount,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        key: Key('invoice-status-${invoice.id}'),
                        style: TextStyle(fontSize: 10, color: statusColor),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (showActions && invoice.status == InvoiceStatus.draft) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: isBusy ? null : () => onReview?.call(invoice),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review & send request'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
          if (showActions && invoice.status == InvoiceStatus.awaiting) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (invoice.approvalUrl != null)
                  OutlinedButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => onOpenCheckout?.call(invoice),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open PayPal'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                FilledButton.tonalIcon(
                  onPressed: isBusy ? null : () => onVerify?.call(invoice),
                  icon: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: const Text('Verify payment'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh from PayPal',
                  onPressed: isBusy ? null : () => onRefresh?.call(invoice),
                  icon: const Icon(Icons.refresh_rounded),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
              ],
            ),
          ],
          if (showActions && invoice.status == InvoiceStatus.processing) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (invoice.paypalOrderId == null)
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => onReview?.call(invoice),
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Resume checkout'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => onVerify?.call(invoice),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verify payment'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                IconButton(
                  tooltip: 'Refresh from PayPal',
                  onPressed: isBusy ? null : () => onRefresh?.call(invoice),
                  icon: const Icon(Icons.refresh_rounded),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BrandMonogram(),
        SizedBox(width: 10),
        Text(
          'AlvaPay',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }
}

class _BrandMonogram extends StatelessWidget {
  const _BrandMonogram();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AlvaPay',
      child: Container(
        width: 31,
        height: 31,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? _darkCanvas
              : _forest,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Center(
          child: Text(
            'A',
            style: TextStyle(
              color: _gold,
              fontFamily: 'serif',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _SandboxPill extends StatelessWidget {
  const _SandboxPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: Color(0xFF5B8669), size: 7),
          SizedBox(width: 6),
          Text(
            'SANDBOX',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1,
              color: context.appText,
            ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.appMutedText,
        fontSize: 10,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: context.appMutedText, size: 24),
          const SizedBox(height: 9),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appMutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: const Icon(Icons.arrow_outward_rounded, size: 14),
      label: Text(label),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      side: BorderSide(color: context.appBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}

ButtonStyle _primaryButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: context.appAccent,
    foregroundColor: context.appOnAccent,
    minimumSize: const Size(48, 50),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(fontWeight: FontWeight.w600),
  );
}

String _money(int cents, String currency) {
  final value = (cents / 100).toStringAsFixed(2);
  return '$currency $value';
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}
