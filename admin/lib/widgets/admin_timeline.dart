import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';

import '../widgets/admin_ui.dart';

class AdminTimeline extends StatelessWidget {
  const AdminTimeline({super.key, required this.events});

  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const AdminEmptyState(message: 'No activity recorded yet.', icon: Icons.timeline);
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = events[i];
        final type = e['type']?.toString() ?? 'event';
        final action = e['action']?.toString() ?? '—';
        final at = adminFormatDateTime(e['at']);
        final color = switch (type) {
          'order' => AppUi.bluePrimary,
          'audit' => AppUi.accentCyan,
          _ => adminMutedTextColor(context),
        };

        return AdminGlassCard(
          padding: const EdgeInsets.all(14),
          accent: color,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                type == 'order' ? Icons.receipt_long_outlined : Icons.history,
                size: 18,
                color: color,
              ),
              AppUi.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(at, style: adminCaptionTextStyle(context)),
                    if (e['detail'] != null)
                      Text(
                        e['detail'].toString(),
                        style: adminCaptionTextStyle(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
