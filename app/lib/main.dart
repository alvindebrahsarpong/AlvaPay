import 'package:flutter/material.dart';

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

enum InvoiceStatus { draft, awaiting, paid }

class Invoice {
  const Invoice({
    required this.client,
    required this.customerEmail,
    required this.description,
    required this.amountCents,
    required this.dueDate,
    required this.status,
    required this.currency,
  });

  final String client;
  final String customerEmail;
  final String description;
  final int amountCents;
  final DateTime dueDate;
  final InvoiceStatus status;
  final String currency;

  String get amount => '$currency ${(amountCents / 100).toStringAsFixed(2)}';
}

final _sampleInvoices = <Invoice>[
  Invoice(
    client: 'Morrow Studio',
    customerEmail: 'accounts@morrow.example.test',
    description: 'Brand identity · Phase II',
    amountCents: 325000,
    dueDate: DateTime(2026, 10, 24),
    status: InvoiceStatus.awaiting,
    currency: 'USD',
  ),
  Invoice(
    client: 'Juniper Coffee',
    customerEmail: 'billing@juniper.example.test',
    description: 'October campaign',
    amountCents: 118000,
    dueDate: DateTime(2026, 10, 12),
    status: InvoiceStatus.paid,
    currency: 'USD',
  ),
  Invoice(
    client: 'Atelier Thorne',
    customerEmail: 'studio@atelierthorne.example.test',
    description: 'Product photography',
    amountCents: 78000,
    dueDate: DateTime(2026, 10, 29),
    status: InvoiceStatus.awaiting,
    currency: 'USD',
  ),
];

class AlvaPayApp extends StatefulWidget {
  const AlvaPayApp({super.key});

  @override
  State<AlvaPayApp> createState() => _AlvaPayAppState();
}

class _AlvaPayAppState extends State<AlvaPayApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  ThemeMode _themeMode = ThemeMode.light;
  int _selectedIndex = 0;
  final List<Invoice> _invoices = List.of(_sampleInvoices);

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  void _openComposer() {
    final sheetContext = _navigatorKey.currentContext;
    if (sheetContext == null) return;
    showModalBottomSheet<Invoice>(
      context: sheetContext,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const InvoiceComposer(),
    ).then((invoice) {
      if (invoice == null || !mounted) return;
      setState(() {
        _invoices.insert(0, invoice);
        _selectedIndex = 1;
      });
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Draft saved. Review it before checkout.'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _forest,
        brightness: _themeMode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
        surface: _themeMode == ThemeMode.dark
            ? const Color(0xFF17211F)
            : _paper,
      ),
      textTheme: ThemeData(
        brightness: _themeMode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ).textTheme.apply(bodyColor: _ink, displayColor: _ink),
      dividerColor: _line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _themeMode == ThemeMode.dark
            ? const Color(0xFF202C29)
            : _canvas,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: _muted),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _line),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _forest, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _themeMode == ThemeMode.dark
            ? const Color(0xFF17211F)
            : _paper,
        indicatorColor: _mint,
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
                              child: _currentPage(),
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
          if (!isWide) const _BrandMark(),
          if (!isWide) const Spacer(),
          const _SandboxPill(),
          SizedBox(width: isWide ? 12 : 4),
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
          if (isWide) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 18,
              backgroundColor: _mint,
              child: Text(
                'A',
                style: TextStyle(color: _forest, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _desktopNavigation() {
    return Container(
      width: 244,
      decoration: const BoxDecoration(
        color: _paper,
        border: Border(right: BorderSide(color: _line)),
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
              color: _canvas,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: _forest, size: 20),
                SizedBox(height: 12),
                Text(
                  'A little more peace of mind.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 5),
                Text(
                  'Checkout stays in the sandbox until you are ready.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'ALVAPAY  ·  PREVIEW',
            style: TextStyle(color: _muted, fontSize: 10),
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
        color: selected ? _mint.withValues(alpha: 0.65) : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = index),
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(icon, size: 20, color: selected ? _forest : _muted),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? _forest : _muted,
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
      1 => InvoiceList(invoices: _invoices, onCreateInvoice: _openComposer),
      2 => const AssistantPage(),
      _ => DashboardPage(
        invoices: _invoices,
        onCreateInvoice: _openComposer,
        onOpenInvoices: () => setState(() => _selectedIndex = 1),
        onOpenAssistant: () => setState(() => _selectedIndex = 2),
      ),
    };
  }
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
    final awaiting = invoices
        .where((invoice) => invoice.status == InvoiceStatus.awaiting)
        .fold<int>(0, (total, invoice) => total + invoice.amountCents);
    final collected = invoices
        .where((invoice) => invoice.status == InvoiceStatus.paid)
        .fold<int>(0, (total, invoice) => total + invoice.amountCents);
    final recent = invoices.take(3).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(isWide ? 38 : 20, 18, isWide ? 38 : 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Eyebrow('THURSDAY  ·  OCTOBER 15'),
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
                  style: _primaryButtonStyle(),
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
                style: _primaryButtonStyle(),
              ),
            ),
          ],
          const SizedBox(height: 26),
          _MomentumCard(
            awaitingCents: awaiting,
            collectedCents: collected,
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
                          '${invoices.where((i) => i.status == InvoiceStatus.awaiting).length}',
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
          const Text(
            'Illustrative preview data · Connect your account for live payment records.',
            style: TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _MomentumCard extends StatelessWidget {
  const _MomentumCard({
    required this.awaitingCents,
    required this.collectedCents,
    required this.onOpenAssistant,
  });

  final int awaitingCents;
  final int collectedCents;
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _BrandMonogram(),
            const SizedBox(width: 10),
            const Text(
              'YOUR MOMENTUM',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                letterSpacing: 1.8,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                'SAMPLE',
                style: TextStyle(color: _gold, fontSize: 9, letterSpacing: 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          _money(awaitingCents, 'USD'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 38,
            height: 1,
            letterSpacing: -1.3,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Still on its way to you',
          style: TextStyle(color: Colors.white70, fontSize: 13),
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
                '${_money(collectedCents, 'USD')} collected',
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
        color: _forest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _forest.withValues(alpha: 0.12),
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
    return Container(
      constraints: const BoxConstraints(minWidth: 145),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: _line),
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
                  color: accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: _forest),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 11, color: _muted),
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
          Text(caption, style: const TextStyle(fontSize: 11, color: _muted)),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.invoices});

  final List<Invoice> invoices;

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Nothing here just yet',
        message: 'Your next invoice will feel right at home.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var index = 0; index < invoices.length; index++) ...[
            _InvoiceRow(invoice: invoices[index]),
            if (index != invoices.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, color: _line),
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
    super.key,
  });

  final List<Invoice> invoices;
  final VoidCallback onCreateInvoice;

  @override
  State<InvoiceList> createState() => _InvoiceListState();
}

class _InvoiceListState extends State<InvoiceList> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.invoices.where((invoice) {
      return switch (_filter) {
        'Awaiting' => invoice.status == InvoiceStatus.awaiting,
        'Paid' => invoice.status == InvoiceStatus.paid,
        'Drafts' => invoice.status == InvoiceStatus.draft,
        _ => true,
      };
    }).toList();
    return SingleChildScrollView(
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
                style: _primaryButtonStyle(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Every detail, in one thoughtful place.',
            style: TextStyle(color: _muted),
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
                  selectedColor: _mint,
                  side: BorderSide(color: _filter == filter ? _mint : _line),
                  labelStyle: TextStyle(
                    color: _filter == filter ? _forest : _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const _EmptyState(
              icon: Icons.filter_list_off_rounded,
              title: 'No matching invoices',
              message: 'Try another filter or start a fresh draft.',
            )
          else
            _ActivityCard(invoices: filtered),
          const SizedBox(height: 14),
          const Text(
            'Demo invoices are synthetic. Live payment status will be verified by the server.',
            style: TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _controller = TextEditingController();
  final List<String> _messages = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(String text) {
    final message = text.trim();
    if (message.isEmpty) return;
    setState(() {
      _messages.add(message);
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('A THOUGHTFUL SECOND PAIR OF HANDS'),
          const SizedBox(height: 8),
          const Text(
            'Ask Alva',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 36,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'A calmer way to stay close to your cash flow.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BrandMonogram(),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'I can help shape an invoice or make sense of your cash flow. '
                          'Once connected, I’ll use only payment records verified by the server.',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final message in _messages)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _forest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        message,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                if (_messages.isNotEmpty)
                  const _EmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'Your question is ready',
                    message: 'Connect the private AI service to get an answer based on verified account records.',
                  ),
              ],
            ),
          ),
          if (_messages.isEmpty) ...[
            const _Eyebrow('A FEW PLACES TO BEGIN'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SuggestionChip(
                  label: 'Who still owes me?',
                  onTap: () => _send('Who still owes me?'),
                ),
                _SuggestionChip(
                  label: 'Summarize my cash flow',
                  onTap: () => _send('Summarize my cash flow'),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: const InputDecoration(
                    hintText: 'Ask anything about your business…',
                    prefixIcon: Icon(Icons.auto_awesome_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: 'Send question',
                onPressed: () => _send(_controller.text),
                icon: const Icon(Icons.arrow_upward_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: _forest,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(52, 52),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Preview mode · AI answers will be grounded in verified records.',
            style: TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ),
    );
  }
}

class InvoiceComposer extends StatefulWidget {
  const InvoiceComposer({super.key});

  @override
  State<InvoiceComposer> createState() => _InvoiceComposerState();
}

class _InvoiceComposerState extends State<InvoiceComposer> {
  final _formKey = GlobalKey<FormState>();
  final _client = TextEditingController();
  final _email = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 14));
  String _currency = 'USD';

  @override
  void dispose() {
    _client.dispose();
    _email.dispose();
    _description.dispose();
    _amount.dispose();
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

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final invoice = Invoice(
      client: _client.text.trim(),
      customerEmail: _email.text.trim(),
      description: _description.text.trim(),
      amountCents: _parseAmount(_amount.text)!,
      dueDate: _dueDate,
      status: InvoiceStatus.draft,
      currency: _currency,
    );
    Navigator.of(context).pop(invoice);
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
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              22,
              14,
              22,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _line,
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
              const Text(
                'Shape the details. Your client never sees a thing until you say so.',
                style: TextStyle(color: _muted, height: 1.4),
              ),
              const SizedBox(height: 22),
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
                      decoration: const InputDecoration(labelText: 'Currency'),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                        DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                        DropdownMenuItem(value: 'GHS', child: Text('GHS')),
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
                  foregroundColor: _ink,
                  side: const BorderSide(color: _line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F3E8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_outlined, size: 18, color: _forest),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AI drafting and PayPal checkout will be enabled when the secure backend is connected. '
                        'This saves a local draft only.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: _ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _save,
                style: _primaryButtonStyle(),
                child: const Text('Save invoice draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (invoice.status) {
      InvoiceStatus.paid => const Color(0xFF347359),
      InvoiceStatus.awaiting => const Color(0xFF9B6B19),
      InvoiceStatus.draft => _muted,
    };
    final statusText = switch (invoice.status) {
      InvoiceStatus.paid => 'Paid',
      InvoiceStatus.awaiting => 'Awaiting',
      InvoiceStatus.draft => 'Draft',
    };
    final statusIcon = switch (invoice.status) {
      InvoiceStatus.paid => Icons.check_circle_outline_rounded,
      InvoiceStatus.awaiting => Icons.schedule_rounded,
      InvoiceStatus.draft => Icons.edit_note_rounded,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _canvas,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 19,
              color: _forest,
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
                  '${invoice.description}  ·  ${_formatDate(invoice.dueDate)}',
                  style: const TextStyle(color: _muted, fontSize: 11),
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
                    style: TextStyle(fontSize: 10, color: statusColor),
                  ),
                ],
              ),
            ],
          ),
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
    return Container(
      width: 31,
      height: 31,
      decoration: BoxDecoration(
        color: _forest,
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
        color: const Color(0xFFEAF0E8),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        children: [
          Icon(Icons.circle, color: Color(0xFF5B8669), size: 7),
          SizedBox(width: 6),
          Text(
            'SANDBOX',
            style: TextStyle(fontSize: 9, letterSpacing: 1, color: _forest),
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
      style: const TextStyle(
        color: _muted,
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
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Icon(icon, color: _muted, size: 24),
          const SizedBox(height: 9),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12),
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
      backgroundColor: Colors.white,
      side: const BorderSide(color: _line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}

ButtonStyle _primaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: _forest,
    foregroundColor: Colors.white,
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
