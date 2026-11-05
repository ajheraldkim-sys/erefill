import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// One stop of the guided tour: a bottom-navigation tab and what it does.
class TourStep {
  const TourStep({required this.tab, required this.title, required this.body});

  /// Index of the bottom-navigation tab to highlight.
  final int tab;
  final String title;
  final String body;
}

/// Remembers per role whether the first-run tour was shown.
abstract final class TourStore {
  static String _key(String role) => 'tour_seen_$role';

  static Future<bool> shouldShow(String role) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_key(role)) ?? false);
  }

  static Future<void> markSeen(String role) async =>
      (await SharedPreferences.getInstance()).setBool(_key(role), true);

  /// "Replay app tour" in settings.
  static Future<void> reset(String role) async =>
      (await SharedPreferences.getInstance()).remove(_key(role));
}

/// Tour copy for each role, one step per bottom tab.
abstract final class AppTourSteps {
  static List<TourStep> forRole(String role) => switch (role) {
        'customer' => const [
            TourStep(
              tab: 0,
              title: 'Home',
              body: 'Reorder in one tap, see recommended stations, or ask eRefill to build your order.',
            ),
            TourStep(
              tab: 1,
              title: 'Stations',
              body: 'Compare stations by rating, price, distance and free-delivery zones. Add water and accessories.',
            ),
            TourStep(
              tab: 2,
              title: 'Chat',
              body: 'Message the station or your rider about an order.',
            ),
            TourStep(
              tab: 3,
              title: 'Orders',
              body: 'Track your rider live, add a tip at checkout, and report a problem within 48 hours.',
            ),
            TourStep(
              tab: 4,
              title: 'Profile',
              body: 'Verify your ID, set theme and text size, and manage addresses and reminders.',
            ),
          ],
        'owner' => const [
            TourStep(tab: 0, title: 'Overview', body: "Today's sales, the 7-day demand forecast and stock at a glance."),
            TourStep(tab: 1, title: 'Orders', body: 'Accept orders, assign riders and follow each delivery.'),
            TourStep(tab: 2, title: 'Stock & Credits', body: 'Track gallons in stock and customer credit.'),
            TourStep(tab: 3, title: 'Riders', body: 'Add riders and see their performance.'),
            TourStep(
              tab: 4,
              title: 'Station',
              body: 'Verify your station, set delivery coverage, sell accessories, upload water tests and answer reports.',
            ),
          ],
        'rider' => const [
            TourStep(tab: 0, title: 'Overview', body: 'Your earnings, tips and today’s deliveries.'),
            TourStep(tab: 1, title: 'Dispatch', body: 'Active jobs. With 2 or more, tap Optimize route for the best order.'),
            TourStep(tab: 2, title: 'Logs', body: 'Past deliveries and earnings.'),
            TourStep(tab: 3, title: 'Messages', body: 'Chat with customers and your station.'),
            TourStep(tab: 4, title: 'Profile', body: 'Theme, text size and account settings.'),
          ],
        _ => const [],
      };
}

/// Lightweight coach marks over the bottom navigation bar.
abstract final class AppTour {
  /// Shows the tour once for [role] (no-op if already seen).
  static Future<void> maybeShow(
    BuildContext context, {
    required String role,
    required GlobalKey navBarKey,
    required int tabCount,
  }) async {
    final steps = AppTourSteps.forRole(role);
    if (steps.isEmpty || !await TourStore.shouldShow(role)) return;
    if (!context.mounted) return;
    show(context, role: role, navBarKey: navBarKey, steps: steps, tabCount: tabCount);
  }

  static void show(
    BuildContext context, {
    required String role,
    required GlobalKey navBarKey,
    required List<TourStep> steps,
    required int tabCount,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TourOverlay(
        navBarKey: navBarKey,
        steps: steps,
        tabCount: tabCount,
        onFinish: () {
          entry.remove();
          TourStore.markSeen(role);
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({
    required this.navBarKey,
    required this.steps,
    required this.tabCount,
    required this.onFinish,
  });

  final GlobalKey navBarKey;
  final List<TourStep> steps;
  final int tabCount;
  final VoidCallback onFinish;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _i = 0;

  Rect? _targetRect() {
    final box = widget.navBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    final w = box.size.width / widget.tabCount;
    final tab = widget.steps[_i].tab.clamp(0, widget.tabCount - 1);
    return Rect.fromLTWH(origin.dx + w * tab, origin.dy, w, box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    final rect = _targetRect();
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _SpotlightPainter(rect)),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: rect == null ? 32 : screen.height - rect.top + 12,
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppUi.surfaceOf(context),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_i + 1} of ${widget.steps.length}', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(step.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(step.body, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(onPressed: widget.onFinish, child: const Text('Skip tour')),
                        const Spacer(),
                        FilledButton(
                          onPressed: last ? widget.onFinish : () => setState(() => _i++),
                          child: Text(last ? 'Done' : 'Next'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      dim.addRRect(RRect.fromRectAndRadius(hole!.deflate(4), const Radius.circular(16)));
      dim.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(dim, Paint()..color = const Color(0xB3000000));
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}

/// Settings button: show the guided tour again next time.
class ReplayTourButton extends StatelessWidget {
  const ReplayTourButton({super.key, required this.role});
  final String role;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () async {
            await TourStore.reset(role);
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('The app tour will play next time you open eRefill.')),
            );
          },
          icon: const Icon(Icons.tour_outlined),
          label: const Text('Replay app tour'),
        ),
      );
}
