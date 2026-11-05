import 'package:erefill/features/dashboard/owner/delivery_coverage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements DeliveryCoverageRepository {
  DeliveryCoverage stored = const DeliveryCoverage(
    radiusKm: 1.0,
    barangays: [],
    minGallons: null,
  );
  DeliveryCoverage? saved;

  @override
  Future<DeliveryCoverage> load(String ownerId) async => stored;

  @override
  Future<void> save(String ownerId, DeliveryCoverage coverage) async =>
      saved = coverage;
}

void main() {
  Future<_FakeRepo> pump(WidgetTester tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(MaterialApp(
      home: DeliveryCoverageScreen(
        ownerId: 'o1',
        town: 'Cantilan',
        repository: repo,
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('shows the current free radius', (tester) async {
    await pump(tester);
    expect(find.text('Free within 1.0 km'), findsOneWidget);
  });

  testWidgets('saves radius, barangays and minimum gallons', (tester) async {
    final repo = await pump(tester);

    await tester.drag(find.byType(Slider), const Offset(300, 0));
    await tester.pumpAndSettle();

    final chip = find.byType(FilterChip).first;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('min-gallons')), '6');
    await tester.ensureVisible(find.text('Save coverage'));
    await tester.tap(find.text('Save coverage'));
    await tester.pumpAndSettle();

    expect(repo.saved, isNotNull);
    expect(repo.saved!.radiusKm, greaterThan(1.0));
    expect(repo.saved!.barangays, hasLength(1));
    expect(repo.saved!.minGallons, 6);
  });

  testWidgets('empty minimum gallons saves as no rule', (tester) async {
    final repo = await pump(tester);
    await tester.ensureVisible(find.text('Save coverage'));
    await tester.tap(find.text('Save coverage'));
    await tester.pumpAndSettle();
    expect(repo.saved!.minGallons, isNull);
  });
}
