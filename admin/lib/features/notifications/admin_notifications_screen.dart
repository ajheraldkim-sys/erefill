import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _userIdController = TextEditingController();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _broadcastRole = 'customer';
  String _priority = 'normal';
  bool _sending = false;
  List<Map<String, dynamic>> _admins = [];
  String? _selectedAdminTier;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    try {
      final admins = await context.read<AdminApiService>().listAdmins();
      if (mounted) setState(() => _admins = admins);
    } catch (_) {}
  }

  Future<void> _sendToUser() async {
    if (_userIdController.text.trim().isEmpty || _titleController.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await context.read<AdminApiService>().sendNotification(
            userId: _userIdController.text.trim(),
            title: _titleController.text.trim(),
            content: _contentController.text.trim(),
            priority: _priority,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _broadcast() async {
    if (_titleController.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final count = await context.read<AdminApiService>().broadcastNotification(
            role: _broadcastRole,
            title: _titleController.text.trim(),
            content: _contentController.text.trim(),
            priority: _priority,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sent to $count users')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setTier() async {
    if (_selectedAdminTier == null) return;
    final parts = _selectedAdminTier!.split('|');
    if (parts.length != 2) return;
    try {
      await context.read<AdminApiService>().setAdminTier(parts[0], parts[1]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin tier updated')));
      await _loadAdmins();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      header: const AdminSectionHeader(
        title: 'Notifications & admin roles',
        subtitle: 'Send alerts to users and manage admin access tiers.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _composeCard()),
              AppUi.hGapMd,
              Expanded(child: _broadcastCard()),
            ],
          ),
          if (_admins.isNotEmpty) ...[
            AppUi.vGapLg,
            AdminGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin team', style: adminSectionTitleStyle(context)),
                  AppUi.vGapMd,
                  ..._admins.map(
                    (a) => ListTile(
                      title: Text(a['full_name']?.toString() ?? a['email']?.toString() ?? '—'),
                      subtitle: Text(a['email']?.toString() ?? '—'),
                      trailing: AdminBadge(
                        label: a['admin_tier']?.toString() ?? 'super',
                        color: AppUi.bluePrimary,
                      ),
                    ),
                  ),
                  AppUi.vGapMd,
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Change admin tier'),
                          items: _admins
                              .expand(
                                (a) => [
                                  DropdownMenuItem(
                                    value: '${a['id']}|super',
                                    child: Text('${a['full_name']} → Super'),
                                  ),
                                  DropdownMenuItem(
                                    value: '${a['id']}|support',
                                    child: Text('${a['full_name']} → Support'),
                                  ),
                                ],
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _selectedAdminTier = v),
                        ),
                      ),
                      AppUi.hGapMd,
                      FilledButton(onPressed: _setTier, child: const Text('Apply')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _composeCard() {
    return AdminGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppUi.bluePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.send, size: 18, color: AppUi.bluePrimary),
              ),
              const SizedBox(width: 10),
              Text('Send to Specific User', style: adminSectionTitleStyle(context)),
            ],
          ),
          AppUi.vGapLg,
          AdminTextField(
            controller: _userIdController,
            label: 'Target User ID (UUID)',
            hint: 'e.g. 550e8400-e29b-41d4-a716-446655440000',
            icon: LucideIcons.user,
          ),
          AppUi.vGapMd,
          AdminTextField(
            controller: _titleController,
            label: 'Notification Title',
            hint: 'e.g. Delivery Update or Alert',
            icon: LucideIcons.bell,
          ),
          AppUi.vGapMd,
          AdminTextField(
            controller: _contentController,
            label: 'Message Body',
            hint: 'Enter your message to the recipient…',
            icon: LucideIcons.messageSquare,
            maxLines: 3,
          ),
          AppUi.vGapMd,
          AdminDropdownFormField<String>(
            label: 'Delivery Priority',
            icon: LucideIcons.flag,
            value: _priority,
            items: const [
              DropdownMenuItem(value: 'low', child: Text('Low Priority')),
              DropdownMenuItem(value: 'normal', child: Text('Normal Priority')),
              DropdownMenuItem(value: 'high', child: Text('High Priority')),
              DropdownMenuItem(value: 'urgent', child: Text('Urgent Alert')),
            ],
            onChanged: (v) => setState(() => _priority = v ?? 'normal'),
          ),
          AppUi.vGapLg,
          ShadcnPrimaryButton(
            height: 44,
            isLoading: _sending,
            icon: LucideIcons.send,
            text: 'Send Direct Notification',
            onPressed: _sending ? null : _sendToUser,
          ),
        ],
      ),
    );
  }

  Widget _broadcastCard() {
    return AdminGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppUi.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.radio, size: 18, color: AppUi.accentGreen),
              ),
              const SizedBox(width: 10),
              Text('Broadcast by Role', style: adminSectionTitleStyle(context)),
            ],
          ),
          AppUi.vGapLg,
          AdminDropdownFormField<String>(
            label: 'Target Audience Role',
            icon: LucideIcons.users,
            value: _broadcastRole,
            items: const [
              DropdownMenuItem(value: 'customer', child: Text('All Customers')),
              DropdownMenuItem(value: 'owner', child: Text('All Station Owners')),
              DropdownMenuItem(value: 'rider', child: Text('All Registered Riders')),
            ],
            onChanged: (v) => setState(() => _broadcastRole = v ?? 'customer'),
          ),
          AppUi.vGapMd,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.info, size: 16, color: AppUi.bluePrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Broadcasting dispatches using the Title and Message composed in the left panel.',
                    style: TextStyle(fontSize: 12.5, color: AppUi.textSecondaryOf(context)),
                  ),
                ),
              ],
            ),
          ),
          AppUi.vGapLg,
          ShadcnPrimaryButton(
            height: 44,
            isLoading: _sending,
            icon: LucideIcons.radio,
            text: 'Broadcast to Role Group',
            onPressed: _sending ? null : _broadcast,
          ),
        ],
      ),
    );
  }
}
