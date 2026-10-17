import 'package:erefill/core/constants.dart';
import 'package:erefill/core/models/app_version_models.dart';
import 'package:erefill/features/update/screens/mandatory_update_screen.dart';
import 'package:erefill/features/update/widgets/optional_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

class AppReleasesScreen extends StatefulWidget {
  const AppReleasesScreen({super.key});

  @override
  State<AppReleasesScreen> createState() => _AppReleasesScreenState();
}

class _AppReleasesScreenState extends State<AppReleasesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _releases = [];
  String _platformFilter = 'all';
  String _statusFilter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadReleases();
  }

  Future<void> _loadReleases() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AdminApiService>();
      final list = await api.listAppReleases();
      if (!mounted) return;
      setState(() {
        _releases = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredReleases {
    return _releases.where((r) {
      final platform = (r['platform'] ?? '').toString().toLowerCase();
      final status = (r['status'] ?? '').toString().toLowerCase();
      final version = (r['version'] ?? '').toString().toLowerCase();
      final title = (r['title'] ?? '').toString().toLowerCase();
      final notes = (r['release_notes'] ?? '').toString().toLowerCase();

      if (_platformFilter != 'all' && platform != _platformFilter) return false;
      if (_statusFilter != 'all' && status != _statusFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final match =
            version.contains(query) ||
            title.contains(query) ||
            notes.contains(query);
        if (!match) return false;
      }
      return true;
    }).toList();
  }

  Map<String, dynamic>? get _activeAndroidRelease {
    for (final r in _releases) {
      if (r['platform'] == 'android' &&
          r['status'] == 'published' &&
          r['is_active'] == true) {
        return r;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeAndroidRelease;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            title: 'Application Releases & Version Management',
            subtitle:
                'Manage production releases, enforce mandatory security updates, verify cryptographic SHA-256 signatures, and inspect release audit logs.',
            trailing: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openAuditLogsModal(context),
                  icon: const Icon(LucideIcons.fileText, size: 16),
                  label: const Text('Audit Logs'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openPreviewModal(context, active),
                  icon: const Icon(LucideIcons.eye, size: 16),
                  label: const Text('Preview Screens'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _openReleaseForm(context),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('New Release'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppUi.bluePrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // KPIs Overview
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: isNarrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 48) / 4,
                    child: AdminKpiTile(
                      label: 'Active Android Version',
                      value: active != null
                          ? 'v${active['version']}+${active['build_number']}'
                          : 'None Active',
                      icon: LucideIcons.smartphone,
                      color: AppUi.bluePrimary,
                    ),
                  ),
                  SizedBox(
                    width: isNarrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 48) / 4,
                    child: AdminKpiTile(
                      label: 'Min Supported Version',
                      value: active != null
                          ? '>= v${active['min_supported_version']}+${active['min_supported_build']}'
                          : 'N/A',
                      icon: LucideIcons.shieldCheck,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  SizedBox(
                    width: isNarrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 48) / 4,
                    child: AdminKpiTile(
                      label: 'Enforcement Policy',
                      value: active != null
                          ? (active['update_type'] == 'mandatory'
                                ? 'Mandatory Gate'
                                : 'Optional Notice')
                          : 'Standard',
                      icon: LucideIcons.circleAlert,
                      color: active?['update_type'] == 'mandatory'
                          ? const Color(0xFFEF4444)
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                  SizedBox(
                    width: isNarrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 48) / 4,
                    child: AdminKpiTile(
                      label: 'Total Release History',
                      value: '${_releases.length} Builds',
                      icon: LucideIcons.layers,
                      color: const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // Search and Filters Card
          AdminGlassCard(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search versions, titles, notes...',
                      prefixIcon: const Icon(LucideIcons.search, size: 16),
                      isDense: true,
                      filled: true,
                      fillColor: AppUi.pageBgOf(context),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppUi.borderOf(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppUi.borderOf(context)),
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Platform: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    DropdownButton<String>(
                      value: _platformFilter,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Platforms'),
                        ),
                        DropdownMenuItem(
                          value: 'android',
                          child: Text('Android (APK)'),
                        ),
                        DropdownMenuItem(value: 'ios', child: Text('iOS')),
                        DropdownMenuItem(
                          value: 'web',
                          child: Text('Web Deployment'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _platformFilter = val);
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Status: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    DropdownButton<String>(
                      value: _statusFilter,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Statuses'),
                        ),
                        DropdownMenuItem(
                          value: 'published',
                          child: Text('Published'),
                        ),
                        DropdownMenuItem(value: 'draft', child: Text('Draft')),
                        DropdownMenuItem(
                          value: 'deprecated',
                          child: Text('Deprecated'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _statusFilter = val);
                      },
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Refresh list',
                  onPressed: _loadReleases,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Release List
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            AdminGlassCard(
              accent: AppUi.error,
              child: Column(
                children: [
                  const Icon(
                    LucideIcons.triangleAlert,
                    color: AppUi.error,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load releases: $_error',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadReleases,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (_filteredReleases.isEmpty)
            AdminGlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 48,
                  horizontal: 24,
                ),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.packageOpen,
                      size: 48,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No Releases Found',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a new release to distribute application updates to users.',
                      style: TextStyle(color: AppUi.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _openReleaseForm(context),
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('Create First Release'),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredReleases.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final r = _filteredReleases[index];
                return _buildReleaseItemCard(context, r);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReleaseItemCard(BuildContext context, Map<String, dynamic> r) {
    final id = r['id']?.toString() ?? '';
    final platform = r['platform']?.toString().toUpperCase() ?? 'ANDROID';
    final channel = r['channel']?.toString() ?? 'official_apk';
    final version = r['version']?.toString() ?? '1.0.0';
    final build = r['build_number']?.toString() ?? '1';
    final minVer = r['min_supported_version']?.toString() ?? '1.0.0';
    final minBuild = r['min_supported_build']?.toString() ?? '1';
    final title = r['title']?.toString() ?? 'Release';
    final notes = r['release_notes']?.toString() ?? '';
    final updateType = r['update_type']?.toString() ?? 'optional';
    final status = r['status']?.toString() ?? 'draft';
    final isActive = r['is_active'] == true;
    final downloadUrl = r['download_url']?.toString() ?? '';
    final checksum = r['checksum_sha256']?.toString() ?? '';
    final publishedAt = r['published_at'] != null
        ? DateFormat(
            'MMM d, yyyy · HH:mm',
          ).format(DateTime.parse(r['published_at'].toString()))
        : null;

    final isMandatory = updateType == 'mandatory';
    final isPublished = status == 'published';

    return AdminGlassCard(
      accent: isActive
          ? const Color(0xFF10B981)
          : (isMandatory ? const Color(0xFFEF4444) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : AppUi.bluePrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isActive ? LucideIcons.circleCheck : LucideIcons.package,
                  color: isActive ? const Color(0xFF10B981) : AppUi.bluePrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'v$version (Build $build)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        _buildBadge(platform, Colors.blueGrey),
                        _buildBadge(
                          channel.replaceAll('_', ' '),
                          Colors.indigo,
                        ),
                        if (isActive)
                          _buildBadge(
                            'ACTIVE IN PRODUCTION',
                            const Color(0xFF10B981),
                          )
                        else
                          _buildBadge(
                            status.toUpperCase(),
                            isPublished ? Colors.blue : Colors.amber,
                          ),
                        _buildBadge(
                          isMandatory ? 'MANDATORY UPDATE' : 'OPTIONAL UPDATE',
                          isMandatory ? const Color(0xFFEF4444) : Colors.teal,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (publishedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Published on $publishedAt',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (!isPublished) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () => _confirmPublishRelease(context, r),
                      icon: const Icon(LucideIcons.send, size: 14),
                      label: const Text('Publish'),
                    ),
                    IconButton(
                      tooltip: 'Edit release draft',
                      onPressed: () => _openReleaseForm(context, existing: r),
                      icon: const Icon(LucideIcons.pencil, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Delete release draft',
                      onPressed: () => _confirmDeleteRelease(context, id),
                      icon: const Icon(
                        LucideIcons.trash2,
                        size: 18,
                        color: AppUi.error,
                      ),
                    ),
                  ] else ...[
                    if (!isActive)
                      OutlinedButton.icon(
                        onPressed: () => _confirmActivateRelease(context, r),
                        icon: const Icon(LucideIcons.check, size: 14),
                        label: const Text('Set Active'),
                      ),
                    IconButton(
                      tooltip: 'Edit release details',
                      onPressed: () => _openReleaseForm(context, existing: r),
                      icon: const Icon(LucideIcons.settings, size: 18),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Release Specification Details
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 750;
              return Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: isNarrow ? constraints.maxWidth : 300,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MINIMUM SUPPORTED CLIENT:',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Requires >= v$minVer (Build $minBuild)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isMandatory
                                ? const Color(0xFFDC2626)
                                : AppUi.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'DISTRIBUTION ENDPOINT:',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: downloadUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Download URL copied to clipboard',
                                ),
                              ),
                            );
                          },
                          child: Text(
                            downloadUrl,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppUi.bluePrimary,
                              decoration: TextDecoration.underline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: isNarrow
                        ? constraints.maxWidth
                        : constraints.maxWidth - 340,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RELEASE NOTES & HIGHLIGHTS:',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notes.isEmpty ? 'No release notes provided.' : notes,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppUi.textSecondaryOf(context),
                          ),
                        ),
                        if (checksum.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                LucideIcons.fingerprint,
                                size: 14,
                                color: Colors.blueGrey,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'SHA-256: $checksum',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                iconSize: 14,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Copy SHA-256 Checksum',
                                icon: const Icon(LucideIcons.copy, size: 14),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: checksum),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('SHA-256 Checksum copied'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // --- Dialogs & Operations ---

  Future<void> _confirmPublishRelease(
    BuildContext context,
    Map<String, dynamic> r,
  ) async {
    final isMandatory = r['update_type'] == 'mandatory';
    final version = r['version'];
    final minVer = r['min_supported_version'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isMandatory ? LucideIcons.triangleAlert : LucideIcons.send,
              color: isMandatory ? AppUi.error : AppUi.bluePrimary,
            ),
            const SizedBox(width: 12),
            const Text('Publish App Release'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to publish version $version to production?',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              if (isMandatory)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppUi.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppUi.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.shieldAlert,
                        color: AppUi.error,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'MANDATORY UPDATE ENFORCEMENT: Any active user on a version older than v$minVer will be immediately blocked by the routing guard and forced to install this update before accessing the application.',
                          style: const TextStyle(
                            color: AppUi.error,
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppUi.bluePrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppUi.bluePrimary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'This release is OPTIONAL. Users will be gently prompted to update when starting the app or viewing announcements, but will not be locked out.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isMandatory
                  ? AppUi.error
                  : const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publish Release'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final api = context.read<AdminApiService>();
        await api.publishAppRelease(r['id']);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Version $version successfully published to production!',
            ),
          ),
        );
        _loadReleases();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish release: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmActivateRelease(
    BuildContext context,
    Map<String, dynamic> r,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Active Release'),
        content: Text(
          'Set version ${r['version']} as the active release for platform ${r['platform']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set Active'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final api = context.read<AdminApiService>();
        await api.publishAppRelease(r['id']);
        if (!mounted) return;
        _loadReleases();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppUi.error),
        );
      }
    }
  }

  Future<void> _confirmDeleteRelease(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Release Draft'),
        content: const Text(
          'Are you sure you want to permanently delete this release draft?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final api = context.read<AdminApiService>();
        await api.deleteAppRelease(id);
        if (!mounted) return;
        _loadReleases();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete draft: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _openReleaseForm(
    BuildContext context, {
    Map<String, dynamic>? existing,
  }) async {
    final isEdit = existing != null;
    final platformCtl = TextEditingController(
      text: existing?['platform']?.toString() ?? 'android',
    );
    final channelCtl = TextEditingController(
      text: existing?['channel']?.toString() ?? 'official_apk',
    );
    final versionCtl = TextEditingController(
      text: existing?['version']?.toString() ?? '1.0.1',
    );
    final buildCtl = TextEditingController(
      text: existing?['build_number']?.toString() ?? '2',
    );
    final minVersionCtl = TextEditingController(
      text: existing?['min_supported_version']?.toString() ?? '1.0.0',
    );
    final minBuildCtl = TextEditingController(
      text: existing?['min_supported_build']?.toString() ?? '1',
    );
    final titleCtl = TextEditingController(
      text: existing?['title']?.toString() ?? 'eRefill Release Update',
    );
    final notesCtl = TextEditingController(
      text:
          existing?['release_notes']?.toString() ??
          '- Performance improvements\n- Enhanced delivery fee calculation\n- Security updates',
    );
    final updateTypeCtl = TextEditingController(
      text: existing?['update_type']?.toString() ?? 'optional',
    );
    final urlCtl = TextEditingController(
      text:
          existing?['download_url']?.toString() ??
          'https://erefill-landing.pages.dev/downloads/eRefill.apk',
    );
    final checksumCtl = TextEditingController(
      text: existing?['checksum_sha256']?.toString() ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(
              isEdit
                  ? 'Edit Release Details'
                  : 'Create New Application Release',
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: platformCtl.text,
                            decoration: const InputDecoration(
                              labelText: 'Platform',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'android',
                                child: Text('Android'),
                              ),
                              DropdownMenuItem(
                                value: 'ios',
                                child: Text('iOS'),
                              ),
                              DropdownMenuItem(
                                value: 'web',
                                child: Text('Web'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => platformCtl.text = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: channelCtl.text,
                            decoration: const InputDecoration(
                              labelText: 'Distribution Channel',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'official_apk',
                                child: Text('Official APK'),
                              ),
                              DropdownMenuItem(
                                value: 'google_play',
                                child: Text('Google Play'),
                              ),
                              DropdownMenuItem(
                                value: 'web_deployment',
                                child: Text('Web Deployment'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => channelCtl.text = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: versionCtl,
                            decoration: const InputDecoration(
                              labelText: 'Version Name',
                              hintText: 'e.g. 1.0.1',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: buildCtl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Build Number',
                              hintText: 'e.g. 2',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minVersionCtl,
                            decoration: const InputDecoration(
                              labelText: 'Min Supported Version',
                              hintText: 'e.g. 1.0.0',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: minBuildCtl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Min Supported Build',
                              hintText: 'e.g. 1',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: updateTypeCtl.text,
                      decoration: const InputDecoration(
                        labelText: 'Update Enforcement Type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'optional',
                          child: Text(
                            'Optional (Dismissible dialog, standard flow)',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'mandatory',
                          child: Text(
                            'Mandatory (Locks previous versions, non-dismissible)',
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => updateTypeCtl.text = v);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: titleCtl,
                      decoration: const InputDecoration(
                        labelText: 'Release Title',
                        hintText:
                            'e.g. Critical Security & Delivery System Update',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: urlCtl,
                      decoration: const InputDecoration(
                        labelText: 'Direct Download URL (HTTPS)',
                        hintText:
                            'https://erefill-landing.pages.dev/downloads/eRefill.apk',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: checksumCtl,
                      decoration: const InputDecoration(
                        labelText:
                            'Cryptographic SHA-256 Checksum (Optional for verification)',
                        hintText: 'e.g. 8f4b5a2e...',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: notesCtl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Release Notes (Markdown / Bullet points)',
                        hintText:
                            'Highlight new features and security fixes...',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppUi.bluePrimary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isEdit ? 'Save Changes' : 'Create Release Draft'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && mounted) {
      try {
        final api = context.read<AdminApiService>();
        final payload = {
          'platform': platformCtl.text.trim(),
          'channel': channelCtl.text.trim(),
          'version': versionCtl.text.trim(),
          'build_number': int.tryParse(buildCtl.text.trim()) ?? 1,
          'min_supported_version': minVersionCtl.text.trim(),
          'min_supported_build': int.tryParse(minBuildCtl.text.trim()) ?? 1,
          'title': titleCtl.text.trim(),
          'release_notes': notesCtl.text.trim(),
          'update_type': updateTypeCtl.text.trim(),
          'download_url': urlCtl.text.trim(),
          'checksum_sha256': checksumCtl.text.trim().isEmpty
              ? null
              : checksumCtl.text.trim(),
        };

        if (isEdit) {
          await api.updateAppRelease(existing['id'], payload);
        } else {
          payload['status'] = 'draft';
          payload['is_active'] = false;
          await api.createAppRelease(payload);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Release updated' : 'Release draft created'),
          ),
        );
        _loadReleases();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save release: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _openAuditLogsModal(BuildContext context) async {
    showDialog<void>(
      context: context,
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: context.read<AdminApiService>().listAppReleaseAuditLogs(),
        builder: (context, snapshot) {
          final logs = snapshot.data ?? [];
          return AlertDialog(
            title: const Row(
              children: [
                Icon(LucideIcons.history, size: 20),
                SizedBox(width: 10),
                Text('Release Audit Trail & History'),
              ],
            ),
            content: SizedBox(
              width: 650,
              height: 480,
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : logs.isEmpty
                  ? const Center(child: Text('No audit logs recorded yet.'))
                  : ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final action = log['action']?.toString() ?? 'ACTION';
                        final adminEmail =
                            log['admin_email']?.toString() ?? 'System';
                        final createdAt = log['created_at'] != null
                            ? DateFormat('MMM d, yyyy · HH:mm:ss').format(
                                DateTime.parse(log['created_at'].toString()),
                              )
                            : '';
                        final details = log['details']?.toString() ?? '{}';

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppUi.bluePrimary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      action,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppUi.bluePrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    adminEmail,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    createdAt,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppUi.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                details,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: AppUi.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openPreviewModal(BuildContext context, Map<String, dynamic>? active) {
    final policy = AppUpdatePolicy.preview(
      latestVersion: active?['version']?.toString() ?? '1.1.0',
      latestBuild: active != null ? (active['build_number'] as num).toInt() : 2,
      minSupportedVersion:
          active?['min_supported_version']?.toString() ?? '1.0.0',
      minSupportedBuild: active != null
          ? (active['min_supported_build'] as num).toInt()
          : 1,
      title:
          active?['title']?.toString() ??
          'Mandatory Security & Delivery Update',
      releaseNotes:
          active?['release_notes']?.toString() ??
          '- Centralized delivery fee calculation\n- Enhanced real-time notification reliability\n- Critical system security patch',
      downloadUrl:
          active?['download_url']?.toString() ??
          'https://erefill-landing.pages.dev/downloads/eRefill.apk',
      checksumSha256: active?['checksum_sha256']?.toString(),
      isMandatory:
          (active?['update_type']?.toString() ?? 'mandatory') == 'mandatory',
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Preview Update UI Experience'),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Test how the update prompt screens will be experienced by customers and station owners on mobile devices.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 20),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: AppUi.error.withValues(alpha: 0.08),
                leading: const Icon(
                  LucideIcons.shieldAlert,
                  color: AppUi.error,
                ),
                title: const Text(
                  'Preview Mandatory Update Screen',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Full-screen non-dismissible lockout modal',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Preview: Mandatory Update Screen'),
                          leading: IconButton(
                            icon: const Icon(LucideIcons.arrowLeft),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        body: const MandatoryUpdateScreen(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: AppUi.bluePrimary.withValues(alpha: 0.08),
                leading: const Icon(LucideIcons.info, color: AppUi.bluePrimary),
                title: const Text(
                  'Preview Optional Update Dialog',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Dismissible in-app modal prompt'),
                onTap: () {
                  Navigator.pop(ctx);
                  OptionalUpdateDialog.show(context, policy);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
