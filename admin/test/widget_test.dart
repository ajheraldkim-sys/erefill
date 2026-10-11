import 'package:erefill_admin/services/admin_api_service.dart';
import 'package:erefill_admin/features/onboarding/create_dialogs.dart';
import 'package:erefill_admin/utils/csv_export.dart';
import 'package:erefill_admin/widgets/admin_ui.dart';
import 'package:erefill/core/widgets/map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('CsvExport tests', () {
    test('build generates valid CSV rows without escaping', () {
      final headers = ['id', 'name', 'status'];
      final rows = [
        ['1', 'Station A', 'active'],
        ['2', 'Station B', 'inactive'],
      ];
      final csv = CsvExport.build(headers, rows);
      expect(csv.contains('id,name,status'), isTrue);
      expect(csv.contains('1,Station A,active'), isTrue);
      expect(csv.contains('2,Station B,inactive'), isTrue);
    });

    test('build properly escapes commas, quotes, and newlines', () {
      final headers = ['id', 'description'];
      final rows = [
        ['1', 'Clean, pure water'],
        ['2', 'He said "Hello"'],
        ['3', 'Line 1\nLine 2'],
      ];
      final csv = CsvExport.build(headers, rows);
      expect(csv.contains('"Clean, pure water"'), isTrue);
      expect(csv.contains('"He said ""Hello"""'), isTrue);
      expect(csv.contains('"Line 1\nLine 2"'), isTrue);
    });
  });

  group('AdminPagedResult tests', () {
    test('instantiates with rows and total', () {
      const paged = AdminPagedResult<String>(
        rows: ['item1', 'item2'],
        total: 10,
      );
      expect(paged.total, 10);
      expect(paged.rows.length, 2);
      expect(paged.rows.first, 'item1');
    });
  });

  group('Admin UI Formatters', () {
    test('formatPeso handles null, ints, and doubles', () {
      expect(formatPeso(null), '₱0.00');
      expect(formatPeso(0), '₱0.00');
      expect(formatPeso(50), '₱50.00');
      expect(formatPeso(25.5), '₱25.50');
      expect(formatPeso(1234.567), '₱1234.57');
    });

    testWidgets('dark mode uses readable semantic colors and map tiles', (
      tester,
    ) async {
      late Color mutedText;
      late Color errorText;
      late Color pendingStatus;
      late bool darkMapUsesDarkTileBuilder;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              mutedText = adminMutedTextColor(context);
              errorText = adminSemanticErrorColor(context);
              pendingStatus = adminStatusColor(context, 'pending');
              darkMapUsesDarkTileBuilder =
                  AppMapTiles.layer(context: context).tileBuilder != null;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(mutedText, const Color(0xFFB8C9CE));
      expect(errorText, const Color(0xFFFF7B83));
      expect(pendingStatus, const Color(0xFFFBBF24));
      expect(darkMapUsesDarkTileBuilder, isFalse);
    });

    test('adminFormatDateTime handles null, invalid, and valid dates', () {
      expect(adminFormatDateTime(null), '—');
      expect(adminFormatDateTime('invalid-date'), 'invalid-date');
      final formatted = adminFormatDateTime('2026-06-01T12:00:00Z');
      expect(formatted.contains('2026'), isTrue);
      expect(formatted.contains('Jun'), isTrue);
    });
  });

  testWidgets('Admin workspace fits phone, tablet, and desktop widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);

    for (final size in [
      const Size(390, 844),
      const Size(1024, 768),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminWorkspaceLayout(
              header: const AdminSectionHeader(
                title: 'User management',
                subtitle: 'View and manage platform users.',
              ),
              toolbar: AdminToolbar(
                searchController: searchController,
                filters: const [Text('All roles')],
                actions: const [Text('Export'), Text('Create user')],
              ),
              metrics: const AdminMetricStrip(
                items: [
                  AdminMetricItem(
                    label: 'Total users',
                    value: '120',
                    icon: Icons.people,
                    color: Colors.blue,
                  ),
                ],
              ),
              body: const AdminDataPanel(
                title: 'Users',
                child: Center(child: Text('User table')),
              ),
              sidePanel: AdminDetailPanel(
                title: 'User details',
                onClose: () {},
                children: const [AdminDetailRow('Email', 'user@example.com')],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Viewport: $size');
    }
  });

  testWidgets('Scrollable admin page stacks flexible panels on phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminPageScaffold(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 960;
              return Flex(
                direction: wide ? Axis.horizontal : Axis.vertical,
                mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Flexible(
                    fit: wide ? FlexFit.tight : FlexFit.loose,
                    child: const AdminGlassCard(
                      child: SizedBox(
                        height: 120,
                        child: Text('Primary panel'),
                      ),
                    ),
                  ),
                  SizedBox(width: wide ? 16 : 0, height: wide ? 0 : 16),
                  Flexible(
                    fit: wide ? FlexFit.tight : FlexFit.loose,
                    child: const AdminGlassCard(
                      child: SizedBox(
                        height: 120,
                        child: Text('Secondary panel'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Create rider filters searchable assignments by municipality', (
    tester,
  ) async {
    final client = SupabaseClient(
      'http://localhost',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

    await tester.pumpWidget(
      Provider<AdminApiService>.value(
        value: _CreateUserStubApiService(client),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCreateUserDialog(context),
                child: const Text('Open create user'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open create user'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Username *'), findsOneWidget);
    expect(find.text('Complete address *'), findsOneWidget);
    expect(find.text('Nearest landmark'), findsOneWidget);

    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdowns.at(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Station Rider').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.ensureVisible(dropdowns.at(2));
    await tester.tap(dropdowns.at(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Madrid').last);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final assignmentField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Assigned Station / Owner',
    );
    await tester.ensureVisible(assignmentField);
    await tester.tap(assignmentField);
    await tester.enterText(assignmentField, 'Madrid');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Madrid Purified Water — Madrid Owner'), findsOneWidget);
    expect(find.text('Cantilan Spring — Cantilan Owner'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(dropdowns.first);
    await tester.tap(dropdowns.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Station Owner').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Water station name *'), findsOneWidget);
    expect(find.text('Detailed station address *'), findsOneWidget);
    expect(find.text('Primary water type'), findsOneWidget);
    expect(find.text('Assigned Station / Owner'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _CreateUserStubApiService extends AdminApiService {
  _CreateUserStubApiService(super.client);

  static final _owners = [
    {
      'id': 'cantilan-owner',
      'role': 'owner',
      'town': 'Cantilan',
      'station_name': 'Cantilan Spring',
      'full_name': 'Cantilan Owner',
    },
    {
      'id': 'madrid-owner',
      'role': 'owner',
      'town': 'Madrid',
      'station_name': 'Madrid Purified Water',
      'full_name': 'Madrid Owner',
    },
  ];

  @override
  Future<AdminPagedResult<Map<String, dynamic>>> listUsers({
    String? role,
    int limit = 50,
    int offset = 0,
    String? search,
  }) async {
    final rows = _owners.skip(offset).take(limit).toList();
    return AdminPagedResult(total: _owners.length, rows: rows);
  }
}
