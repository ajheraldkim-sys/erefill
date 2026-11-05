import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// On/off for smart refill reminders (profiles.refill_reminders_enabled).
class RefillReminderToggle extends StatefulWidget {
  const RefillReminderToggle({super.key, this.load, this.save});

  final Future<bool> Function()? load;
  final Future<void> Function(bool enabled)? save;

  @override
  State<RefillReminderToggle> createState() => _RefillReminderToggleState();
}

class _RefillReminderToggleState extends State<RefillReminderToggle> {
  bool? _enabled;

  SupabaseClient get _db => Supabase.instance.client;

  Future<bool> _defaultLoad() async {
    final row = await _db
        .from('profiles')
        .select('refill_reminders_enabled')
        .eq('id', _db.auth.currentUser!.id)
        .maybeSingle();
    return row?['refill_reminders_enabled'] != false;
  }

  Future<void> _defaultSave(bool v) => _db
      .from('profiles')
      .update({'refill_reminders_enabled': v})
      .eq('id', _db.auth.currentUser!.id);

  @override
  void initState() {
    super.initState();
    (widget.load ?? _defaultLoad)().then(
      (v) {
        if (mounted) setState(() => _enabled = v);
      },
      onError: (_) {
        // Column missing on older databases: hide the toggle.
      },
    );
  }

  Future<void> _set(bool v) async {
    final before = _enabled;
    setState(() => _enabled = v);
    try {
      await (widget.save ?? _defaultSave)(v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _enabled = before);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not save. Check your connection.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    if (enabled == null) return const SizedBox.shrink();
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Refill reminders'),
      subtitle: const Text('Remind me when I usually run out of water'),
      value: enabled,
      onChanged: _set,
    );
  }
}
