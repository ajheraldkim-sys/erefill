import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/csv_export.dart';
import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';
import '../onboarding/create_dialogs.dart';
import '../stations/station_detail_screen.dart';
import 'user_manage_dialog.dart';

enum UserViewMode { cards, list }

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _searchController = TextEditingController();
  AdminPagedResult<Map<String, dynamic>>? _page;
  final Map<String, Map<int, AdminPagedResult<Map<String, dynamic>>>>
  _pageCache = {};
  Map<String, dynamic>? _selected;
  bool _loading = true;
  String? _error;
  String _rolePill = 'all';
  UserViewMode _viewMode = UserViewMode.cards;
  int _offset = 0;
  int _loadRequestId = 0;
  static const _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _cacheKey(String? role, String search) => '${role ?? 'all'}|$search';

  void _invalidateUserCache() => _pageCache.clear();

  Future<void> _load({bool resetPage = true, bool forceRefresh = true}) async {
    if (resetPage) _offset = 0;
    final roleFilter = _rolePill == 'all' ? null : _rolePill;
    final search = _searchController.text.trim();
    final cacheKey = _cacheKey(roleFilter, search);
    final offset = _offset;
    final requestId = ++_loadRequestId;

    if (forceRefresh) {
      _pageCache.remove(cacheKey);
    } else {
      final cachedPage = _pageCache[cacheKey]?[offset];
      if (cachedPage != null) {
        setState(() {
          _page = cachedPage;
          _loading = false;
          _error = null;
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await context.read<AdminApiService>().listUsers(
        role: roleFilter,
        search: search.isEmpty ? null : search,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || requestId != _loadRequestId) return;
      _pageCache.putIfAbsent(cacheKey, () => {})[offset] = page;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _manageUser(Map<String, dynamic> user) async {
    final changed = await showUserManageDialog(
      context,
      userId: user['id'] as String,
      initial: user,
    );
    if (changed == true) {
      if (_selected?['id'] == user['id']) setState(() => _selected = null);
      _invalidateUserCache();
      await _load(resetPage: false);
    }
  }

  Future<void> _toggleSuspendUser(Map<String, dynamic> user) async {
    final userId = user['id'] as String;
    final isSuspended = user['is_suspended'] == true;
    final name = user['full_name']?.toString() ?? 'this user';
    final api = context.read<AdminApiService>();
    final messenger = ScaffoldMessenger.of(context);

    if (isSuspended) {
      final confirm = await showAdminConfirmDialog(
        context,
        title: 'Unsuspend $name?',
        message:
            'This will restore full access and allow the user to place orders and log in.',
        confirmLabel: 'Unsuspend',
        icon: LucideIcons.lockOpen,
        iconColor: AppUi.accentGreen,
      );
      if (confirm != true || !mounted) return;
      try {
        await api.unsuspendUser(userId, reason: 'Reactivated by admin');
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('User "$name" has been unsuspended.'),
            backgroundColor: AppUi.accentGreen,
          ),
        );
        if (_selected?['id'] == userId) {
          setState(() {
            _selected = Map<String, dynamic>.from(_selected!)
              ..['is_suspended'] = false;
          });
        }
        _invalidateUserCache();
        await _load(resetPage: false);
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppUi.error),
        );
      }
    } else {
      final reason = await showAdminPromptDialog(
        context,
        title: 'Suspend $name?',
        subtitle:
            'User will immediately lose access to place orders and log in',
        icon: LucideIcons.ban,
        iconColor: adminSemanticErrorColor(context),
        label: 'Suspension reason',
        hint: 'Enter reason (e.g., policy violation, fraudulent activity)...',
        confirmLabel: 'Suspend Account',
      );
      if (reason == null || !mounted) return;
      try {
        await api.suspendUser(
          userId,
          reason: reason.isEmpty ? 'Suspended by admin' : reason,
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('User "$name" has been suspended.'),
            backgroundColor: AppUi.error,
          ),
        );
        if (_selected?['id'] == userId) {
          setState(() {
            _selected = Map<String, dynamic>.from(_selected!)
              ..['is_suspended'] = true
              ..['suspended_reason'] = reason;
          });
        }
        _invalidateUserCache();
        await _load(resetPage: false);
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppUi.error),
        );
      }
    }
  }

  Future<void> _openStationForOwner(String ownerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StationDetailScreen(ownerId: ownerId)),
    );
  }

  Future<void> _exportCsv() async {
    final rows = _page?.rows ?? [];
    final csv = CsvExport.build(
      ['id', 'name', 'email', 'phone', 'role', 'town', 'orders'],
      rows
          .map(
            (u) => [
              u['id']?.toString() ?? '',
              u['full_name']?.toString() ?? '',
              u['email']?.toString() ?? '',
              u['phone']?.toString() ?? '',
              u['role']?.toString() ?? '',
              u['town']?.toString() ?? '',
              '${u['order_count'] ?? 0}',
            ],
          )
          .toList(),
    );
    await CsvExport.copyToClipboard(csv);
    final path = await CsvExport.saveToFile(csv, 'erefill_users.csv');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null ? 'Saved to $path' : 'CSV copied to clipboard',
        ),
      ),
    );
  }

  Color _roleColor(BuildContext context, String role) =>
      switch (role.toLowerCase()) {
        'owner' =>
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF56D6A6)
              : AppUi.accentGreen,
        'rider' => AppUi.accentCyan,
        'admin' => const Color(0xFF6366F1),
        'customer' => Theme.of(context).colorScheme.primary,
        _ => adminMutedTextColor(context),
      };

  IconData _roleIcon(String role) => switch (role.toLowerCase()) {
    'owner' => LucideIcons.store,
    'rider' => LucideIcons.bike,
    'admin' => LucideIcons.shieldCheck,
    'customer' => LucideIcons.users,
    _ => LucideIcons.users,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading && _page == null) {
      return const AdminLoadingState();
    }
    if (_error != null) {
      return AdminErrorState(message: _error!, onRetry: () => _load());
    }

    final rows = _page?.rows ?? [];
    final total = _page?.total ?? 0;
    final canPrev = _offset > 0;
    final canNext = _offset + _pageSize < total;

    return AdminWorkspaceLayout(
      header: AdminSectionHeader(
        title: 'Users & Access',
        subtitle: 'Review directory, update roles, and manage permissions.',
        trailing: SegmentedButton<UserViewMode>(
          segments: const [
            ButtonSegment(
              value: UserViewMode.cards,
              icon: Icon(LucideIcons.layoutGrid, size: 16),
              label: Text('Cards'),
            ),
            ButtonSegment(
              value: UserViewMode.list,
              icon: Icon(LucideIcons.tableProperties, size: 16),
              label: Text('List'),
            ),
          ],
          selected: {_viewMode},
          onSelectionChanged: (s) => setState(() => _viewMode = s.first),
        ),
      ),
      toolbar: AdminGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 8),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: compact
                          ? constraints.maxWidth
                          : (constraints.maxWidth * 0.38).clamp(240, 420),
                      child: TextField(
                        controller: _searchController,
                        decoration: AppUi.fieldDecorationOf(
                          context,
                          'Search name, email, phone…',
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                        ).copyWith(isDense: true),
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                    ShadcnOutlineButton(
                      height: 38,
                      onPressed: _exportCsv,
                      icon: LucideIcons.download,
                      text: 'Export CSV',
                    ),
                    ShadcnPrimaryButton(
                      height: 38,
                      onPressed: () async {
                        final created = await showCreateUserDialog(context);
                        if (created == true) {
                          _invalidateUserCache();
                          _load();
                        }
                      },
                      icon: LucideIcons.userPlus,
                      text: 'Create User',
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _load,
                      icon: const Icon(LucideIcons.refreshCw, size: 18),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Mobile-mirrored Role Segmented Pills
            AdminFilterPills<String>(
              selected: _rolePill,
              onSelected: (val) {
                setState(() => _rolePill = val);
                _load(forceRefresh: false);
              },
              items: const [
                AdminFilterPillItem(
                  value: 'all',
                  label: 'All Directory',
                  icon: LucideIcons.users,
                ),
                AdminFilterPillItem(
                  value: 'customer',
                  label: 'Customers',
                  icon: LucideIcons.user,
                ),
                AdminFilterPillItem(
                  value: 'owner',
                  label: 'Station Owners',
                  icon: LucideIcons.store,
                ),
                AdminFilterPillItem(
                  value: 'rider',
                  label: 'Fleet Riders',
                  icon: LucideIcons.bike,
                ),
                AdminFilterPillItem(
                  value: 'admin',
                  label: 'Admins',
                  icon: LucideIcons.shieldCheck,
                ),
              ],
            ),
          ],
        ),
      ),
      metrics: AdminMetricStrip(
        items: [
          AdminMetricItem(
            label: 'Total users in registry',
            value: '$total',
            icon: LucideIcons.users,
            color: AppUi.bluePrimary,
          ),
          AdminMetricItem(
            label: 'Loaded on page',
            value: '${rows.length}',
            icon: LucideIcons.userCheck,
            color: AppUi.accentCyan,
          ),
        ],
      ),
      sidePanel: _selected == null
          ? null
          : AdminDetailPanel(
              title: _selected!['full_name']?.toString() ?? 'User Profile',
              onClose: () => setState(() => _selected = null),
              actions: [
                Expanded(
                  child: AdminManageButton(
                    height: 38,
                    text: 'Manage Access',
                    onPressed: () => _manageUser(_selected!),
                  ),
                ),
                AppUi.hGapSm,
                if (_selected!['is_suspended'] == true)
                  Expanded(
                    child: AdminActivateButton(
                      height: 38,
                      text: 'Unsuspend',
                      onPressed: () => _toggleSuspendUser(_selected!),
                    ),
                  )
                else
                  Expanded(
                    child: AdminSuspendButton(
                      height: 38,
                      text: 'Suspend',
                      onPressed: () => _toggleSuspendUser(_selected!),
                    ),
                  ),
              ],
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: _roleColor(
                      context,
                      _selected!['role']?.toString() ?? '',
                    ).withValues(alpha: 0.15),
                    child: Icon(
                      _roleIcon(_selected!['role']?.toString() ?? ''),
                      size: 32,
                      color: _roleColor(
                        context,
                        _selected!['role']?.toString() ?? '',
                      ),
                    ),
                  ),
                ),
                AppUi.vGapMd,
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AdminBadge(
                      label:
                          _selected!['role']?.toString().toUpperCase() ?? '—',
                      color: _roleColor(
                        context,
                        _selected!['role']?.toString() ?? '',
                      ),
                    ),
                    if (_selected!['is_suspended'] == true) ...[
                      const SizedBox(width: 8),
                      AdminBadge(
                        label: 'SUSPENDED',
                        color: adminSemanticErrorColor(context),
                        icon: LucideIcons.ban,
                      ),
                    ],
                  ],
                ),
                AppUi.vGapLg,
                AdminDetailRow('Email', _selected!['email']?.toString() ?? '—'),
                AdminDetailRow('Phone', _selected!['phone']?.toString() ?? '—'),
                AdminDetailRow(
                  'Username',
                  _selected!['username']?.toString() ?? '—',
                ),
                AdminDetailRow('Town', _selected!['town']?.toString() ?? '—'),
                AdminDetailRow(
                  'Barangay',
                  _selected!['barangay']?.toString() ?? '—',
                ),
                if (_selected!['role']?.toString().toLowerCase() ==
                    'owner') ...[
                  AdminDetailRow(
                    'Station',
                    _selected!['station_name']?.toString() ?? '—',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ShadcnOutlineButton(
                      height: 38,
                      icon: LucideIcons.store,
                      text: 'Open Station Fleet',
                      onPressed: () =>
                          _openStationForOwner(_selected!['id'] as String),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (_selected!['role']?.toString() == 'rider')
                  AdminDetailRow(
                    'Vehicle',
                    _selected!['vehicle_type']?.toString() ?? '—',
                  ),
                AdminDetailRow(
                  'Orders Count',
                  '${_selected!['order_count'] ?? 0}',
                ),
                AdminDetailRow(
                  'Joined',
                  adminFormatDateTime(_selected!['created_at']),
                ),
                AdminDetailRow(
                  'User UUID',
                  _selected!['id']?.toString() ?? '—',
                ),
              ],
            ),
      body: _viewMode == UserViewMode.cards
          ? _cardsBody(rows, total, canPrev, canNext)
          : _listBody(rows, total, canPrev, canNext),
    );
  }

  Widget _cardsBody(
    List<Map<String, dynamic>> rows,
    int total,
    bool canPrev,
    bool canNext,
  ) {
    if (rows.isEmpty) {
      return const AdminEmptyState(
        message: 'No users match the selected role or search query.',
        icon: LucideIcons.users,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 680
            ? 1
            : (constraints.maxWidth < 1180 ? 2 : 3);
        final cardWidth =
            (constraints.maxWidth - ((crossAxisCount - 1) * 16)) /
            crossAxisCount;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: rows.map((u) {
                  final role = (u['role']?.toString() ?? 'customer')
                      .toLowerCase();
                  final roleCol = _roleColor(context, role);
                  final roleIc = _roleIcon(role);
                  final isSelected = _selected?['id'] == u['id'];
                  final isSuspended = u['is_suspended'] == true;
                  final fullName = u['full_name']?.toString() ?? 'User';
                  final initial = fullName.isNotEmpty
                      ? fullName[0].toUpperCase()
                      : 'U';

                  return SizedBox(
                    width: cardWidth,
                    child: AdminGlassCard(
                      padding: const EdgeInsets.all(18),
                      accent: isSelected ? AppUi.bluePrimary : null,
                      onTap: () => setState(() => _selected = u),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: roleCol.withValues(
                                  alpha: 0.14,
                                ),
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: roleCol,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fullName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      u['email']?.toString() ?? 'No email',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppUi.textSecondaryOf(context),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  AdminBadge(
                                    label: role.toUpperCase(),
                                    color: roleCol,
                                    icon: roleIc,
                                  ),
                                  if (isSuspended) ...[
                                    const SizedBox(height: 4),
                                    AdminBadge(
                                      label: 'SUSPENDED',
                                      color: adminSemanticErrorColor(context),
                                      icon: LucideIcons.ban,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.phone,
                                size: 13,
                                color: adminMutedTextColor(context),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                u['phone']?.toString() ?? 'No phone',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              if (u['town'] != null) ...[
                                Icon(
                                  LucideIcons.mapPin,
                                  size: 13,
                                  color: adminMutedTextColor(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${u['town']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              if (role == 'owner') ...[
                                Expanded(
                                  child: ShadcnOutlineButton(
                                    height: 36,
                                    icon: LucideIcons.store,
                                    text: 'Station',
                                    onPressed: () =>
                                        _openStationForOwner(u['id'] as String),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: AdminManageButton(
                                  height: 36,
                                  text: 'Manage',
                                  onPressed: () => _manageUser(u),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isSuspended)
                                AdminActivateButton(
                                  height: 36,
                                  text: 'Unsuspend',
                                  onPressed: () => _toggleSuspendUser(u),
                                )
                              else
                                AdminSuspendButton(
                                  height: 36,
                                  text: 'Suspend',
                                  onPressed: () => _toggleSuspendUser(u),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Pagination controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: canPrev
                        ? () {
                            _offset = (_offset - _pageSize).clamp(0, total);
                            _load(resetPage: false, forceRefresh: false);
                          }
                        : null,
                    icon: const Icon(LucideIcons.chevronLeft, size: 20),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Showing ${_offset + 1}–${(_offset + rows.length).clamp(0, total)} of $total',
                      style: adminCaptionTextStyle(context),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: canNext
                        ? () {
                            _offset += _pageSize;
                            _load(resetPage: false, forceRefresh: false);
                          }
                        : null,
                    icon: const Icon(LucideIcons.chevronRight, size: 20),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _listBody(
    List<Map<String, dynamic>> rows,
    int total,
    bool canPrev,
    bool canNext,
  ) {
    return AdminDataPanel(
      title: 'Users Directory',
      subtitle:
          'Showing ${_offset + 1}–${(_offset + rows.length).clamp(0, total)} of $total',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: canPrev
                ? () {
                    _offset = (_offset - _pageSize).clamp(0, total);
                    _load(resetPage: false, forceRefresh: false);
                  }
                : null,
            icon: const Icon(LucideIcons.chevronLeft, size: 18),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: canNext
                ? () {
                    _offset += _pageSize;
                    _load(resetPage: false, forceRefresh: false);
                  }
                : null,
            icon: const Icon(LucideIcons.chevronRight, size: 18),
          ),
        ],
      ),
      isEmpty: rows.isEmpty,
      child: ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: AppUi.dividerOf(context)),
        itemBuilder: (context, i) {
          final u = rows[i];
          final role = (u['role']?.toString() ?? 'customer').toLowerCase();
          final selected = _selected?['id'] == u['id'];
          final isSuspended = u['is_suspended'] == true;
          final fullName = u['full_name']?.toString() ?? '—';
          final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U';

          return Material(
            color: selected
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.transparent,
            child: ListTile(
              onTap: () => setState(() => _selected = u),
              onLongPress: () => _manageUser(u),
              leading: CircleAvatar(
                backgroundColor: _roleColor(
                  context,
                  role,
                ).withValues(alpha: 0.15),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _roleColor(context, role),
                  ),
                ),
              ),
              title: Text(
                fullName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${u['email']?.toString() ?? '—'} · ${u['phone']?.toString() ?? '—'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSuspended) ...[
                    AdminBadge(
                      label: 'SUSPENDED',
                      color: adminSemanticErrorColor(context),
                      icon: LucideIcons.ban,
                    ),
                    const SizedBox(width: 8),
                  ],
                  AdminBadge(
                    label: role.toUpperCase(),
                    color: _roleColor(context, role),
                  ),
                  const SizedBox(width: 10),
                  AdminManageButton(
                    height: 32,
                    text: 'Manage',
                    onPressed: () => _manageUser(u),
                  ),
                  const SizedBox(width: 6),
                  if (isSuspended)
                    AdminActivateButton(
                      height: 32,
                      compact: true,
                      text: 'Unsuspend user',
                      onPressed: () => _toggleSuspendUser(u),
                    )
                  else
                    AdminSuspendButton(
                      height: 32,
                      compact: true,
                      text: 'Suspend user',
                      onPressed: () => _toggleSuspendUser(u),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
