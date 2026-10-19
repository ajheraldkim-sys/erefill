import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/app_haptics.dart';

class AdminAuditLogView extends StatefulWidget {
  const AdminAuditLogView({super.key});

  @override
  State<AdminAuditLogView> createState() => _AdminAuditLogViewState();
}

class _AdminAuditLogViewState extends State<AdminAuditLogView> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _actionFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await supabase
          .from('audit_logs')
          .select('*')
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() {
        _logs = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _logs.where((l) {
      final action = (l['action'] ?? '').toString().toLowerCase();
      final entity = (l['entity_type'] ?? '').toString().toLowerCase();
      final actor = (l['actor_id'] ?? '').toString().toLowerCase();
      final matchesSearch = _search.isEmpty ||
          action.contains(_search.toLowerCase()) ||
          entity.contains(_search.toLowerCase()) ||
          actor.contains(_search.toLowerCase());

      if (!matchesSearch) return false;
      if (_actionFilter == 'all') return true;
      return action.contains(_actionFilter.toLowerCase()) ||
          entity.contains(_actionFilter.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        backgroundColor: AppUi.surfaceOf(context),
        elevation: 0,
        title: Text(
          'System Audit Trail',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppUi.textPrimaryOf(context),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Logs',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              AppHaptics.light();
              _loadLogs();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            color: AppUi.surfaceOf(context),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search audit events, actions, or admin IDs…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: AppUi.pageBgOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      borderSide: BorderSide(color: AppUi.borderOf(context)),
                    ),
                  ),
                  onChanged: (val) => setState(() => _search = val),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('All Events', 'all'),
                      const SizedBox(width: 8),
                      _chip('Stations', 'station'),
                      const SizedBox(width: 8),
                      _chip('Users', 'user'),
                      const SizedBox(width: 8),
                      _chip('Orders', 'order'),
                      const SizedBox(width: 8),
                      _chip('Config & Fees', 'fee'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppUi.bluePrimary))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppUi.error, size: 40),
                              const SizedBox(height: 8),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              ElevatedButton(onPressed: _loadLogs, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.shield_outlined, size: 48, color: AppUi.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  'No audit records found',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'All administrative actions are captured and logged here.',
                                  style: TextStyle(color: AppUi.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final log = filtered[index];
                              final action = log['action']?.toString() ?? 'SYSTEM_EVENT';
                              final entity = log['entity_type']?.toString() ?? 'general';
                              final actor = log['actor_id']?.toString() ?? 'system';
                              final date = (log['created_at']?.toString() ?? '').split('T').first;
                              final time = (log['created_at']?.toString() ?? '')
                                  .split('T')
                                  .last
                                  .split('.')
                                  .first;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppUi.surfaceOf(context),
                                  borderRadius: AppUi.radiusLg,
                                  border: Border.all(color: AppUi.borderOf(context)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppUi.brandSoftOf(context),
                                            borderRadius: BorderRadius.circular(AppUi.radiusSm),
                                          ),
                                          child: Text(
                                            action.toUpperCase(),
                                            style: TextStyle(
                                              color: AppUi.brandOf(context),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Entity: $entity',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppUi.textSecondaryOf(context),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '$date $time',
                                          style: TextStyle(fontSize: 11, color: AppUi.textMuted),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Actor: ${actor.length > 12 ? "${actor.substring(0, 12)}..." : actor}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppUi.textPrimaryOf(context),
                                      ),
                                    ),
                                    if (log['details'] != null || log['metadata'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Payload: ${log['details'] ?? log['metadata']}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppUi.textMuted,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = _actionFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        AppHaptics.selection();
        setState(() => _actionFilter = value);
      },
      selectedColor: AppUi.brandSoftOf(context),
      checkmarkColor: AppUi.bluePrimary,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: selected ? AppUi.brandOf(context) : AppUi.textSecondaryOf(context),
      ),
    );
  }
}
