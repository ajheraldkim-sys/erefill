import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/app_haptics.dart';

Future<bool?> showAdminBroadcastDialog(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _AdminBroadcastSheet(),
  );
}

class _AdminBroadcastSheet extends StatefulWidget {
  const _AdminBroadcastSheet();

  @override
  State<_AdminBroadcastSheet> createState() => _AdminBroadcastSheetState();
}

class _AdminBroadcastSheetState extends State<_AdminBroadcastSheet> {
  final supabase = Supabase.instance.client;
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _userIdController = TextEditingController();

  String _targetAudience = 'all'; // all, customer, owner, rider, specific
  String _priority = 'normal'; // normal, high, urgent
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _sendBroadcast() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a notification title and message body.'),
          backgroundColor: AppUi.error,
        ),
      );
      return;
    }

    if (_targetAudience == 'specific' && _userIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the target User ID or Email.'),
          backgroundColor: AppUi.error,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    AppHaptics.medium();

    try {
      int recipientsCount = 0;

      if (_targetAudience == 'specific') {
        final target = _userIdController.text.trim();
        await supabase.from('system_notifications').insert({
          'user_id': target,
          'title': title,
          'content': body,
          'priority': _priority,
          'created_at': DateTime.now().toIso8601String(),
        });
        recipientsCount = 1;
      } else {
        // Try RPC first
        try {
          final res = await supabase.rpc(
            'admin_broadcast_notification',
            params: {
              'p_role': _targetAudience == 'all' ? null : _targetAudience,
              'p_title': title,
              'p_content': body,
              'p_priority': _priority,
            },
          );
          recipientsCount = (res as num?)?.toInt() ?? 1;
        } catch (_) {
          // Fallback direct insert
          dynamic query = supabase.from('profiles').select('id');
          if (_targetAudience != 'all') {
            query = query.eq('role', _targetAudience);
          }
          final users = await query;
          final List rows = (users as List).map((u) => {
            'user_id': u['id'],
            'title': title,
            'content': body,
            'priority': _priority,
            'created_at': DateTime.now().toIso8601String(),
          }).toList();

          if (rows.isNotEmpty) {
            await supabase.from('system_notifications').insert(rows);
            recipientsCount = rows.length;
          }
        }
      }

      if (!mounted) return;
      AppHaptics.success();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Broadcast sent successfully to $recipientsCount user(s)!'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Broadcast failed: $e'), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppUi.blueSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: AppUi.bluePrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Broadcast Push Alert',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        'Send real-time alerts to marketplace roles',
                        style: TextStyle(fontSize: 12, color: AppUi.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Target Audience',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _audienceChip('All Users', 'all'),
                  const SizedBox(width: 8),
                  _audienceChip('Customers', 'customer'),
                  const SizedBox(width: 8),
                  _audienceChip('Station Owners', 'owner'),
                  const SizedBox(width: 8),
                  _audienceChip('Delivery Riders', 'rider'),
                  const SizedBox(width: 8),
                  _audienceChip('Specific User', 'specific'),
                ],
              ),
            ),
            if (_targetAudience == 'specific') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _userIdController,
                decoration: InputDecoration(
                  labelText: 'User ID or Email',
                  hintText: 'Enter user profile ID…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Alert Headline / Title',
                hintText: 'e.g., Scheduled Maintenance Notice',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: InputDecoration(
                labelText: 'Message Body',
                hintText: 'Type your message text here…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Priority: ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(width: 8),
                _priorityChip('Normal', 'normal', Colors.blue),
                const SizedBox(width: 6),
                _priorityChip('High', 'high', Colors.amber),
                const SizedBox(width: 6),
                _priorityChip('Urgent', 'urgent', Colors.red),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _sendBroadcast,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppUi.bluePrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _sending ? 'Broadcasting...' : 'Broadcast Alert Now',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audienceChip(String label, String value) {
    final selected = _targetAudience == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        AppHaptics.selection();
        setState(() => _targetAudience = value);
      },
      selectedColor: AppUi.blueSoft,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? AppUi.bluePrimary : AppUi.textSecondaryOf(context),
      ),
    );
  }

  Widget _priorityChip(String label, String value, Color color) {
    final selected = _priority == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        AppHaptics.selection();
        setState(() => _priority = value);
      },
      selectedColor: color.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: selected ? color : AppUi.textSecondaryOf(context),
      ),
    );
  }
}
