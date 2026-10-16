import 'package:erefill/core/constants.dart';
import 'package:erefill/core/models/app_version_models.dart';
import 'package:erefill/core/utils/app_haptics.dart';
import 'package:erefill/features/update/screens/mandatory_update_screen.dart';
import 'package:erefill/features/update/widgets/optional_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminReleasesView extends StatefulWidget {
  const AdminReleasesView({super.key});

  @override
  State<AdminReleasesView> createState() => _AdminReleasesViewState();
}

class _AdminReleasesViewState extends State<AdminReleasesView> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _releases = [];

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
      final rows = await _supabase
          .from('app_releases')
          .select('*')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _releases = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? get _activeRelease {
    for (final r in _releases) {
      if (r['is_active'] == true && r['status'] == 'published') {
        return r;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeRelease;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        title: const Text(
          'App Releases & Versions',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Audit Logs',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => _showAuditLogs(context),
          ),
          IconButton(
            tooltip: 'Preview Screens',
            icon: const Icon(Icons.remove_red_eye_rounded),
            onPressed: () => _showPreviewOptions(context, active),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadReleases,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppUi.bluePrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Release'),
        onPressed: _openCreateReleaseDialog,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppUi.bluePrimary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppUi.error, size: 48),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadReleases,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadReleases,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      // Active Production Policy Card
                      if (active != null) _buildActiveCard(context, active),
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'All Releases (${_releases.length})',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (_releases.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: Text(
                            'No releases registered yet.',
                            style: TextStyle(color: AppUi.textSecondaryOf(context)),
                          ),
                        )
                      else
                        ..._releases.map((r) => _buildReleaseCard(context, r)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildActiveCard(BuildContext context, Map<String, dynamic> active) {
    final version = active['version'] ?? '1.0.0';
    final build = active['build_number'] ?? '1';
    final minVer = active['min_supported_version'] ?? '1.0.0';
    final minBuild = active['min_supported_build'] ?? '1';
    final updateType = active['update_type']?.toString() ?? 'optional';
    final isMandatory = updateType == 'mandatory';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMandatory ? AppUi.error.withValues(alpha: 0.4) : AppUi.accentGreen.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isMandatory ? AppUi.error : AppUi.accentGreen).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isMandatory ? Icons.shield_rounded : Icons.check_circle_rounded,
                  color: isMandatory ? AppUi.error : AppUi.accentGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Active Production Policy',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      isMandatory
                          ? 'Mandatory Enforcement Gate Active'
                          : 'Optional Notice Policy',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isMandatory ? AppUi.error : AppUi.accentGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricColumn('Current Version', 'v$version+$build'),
              _buildMetricColumn('Min Required', 'v$minVer+$minBuild'),
              _buildMetricColumn('Platform', (active['platform'] ?? 'Android').toString().toUpperCase()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppUi.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildReleaseCard(BuildContext context, Map<String, dynamic> r) {
    final version = r['version'] ?? '1.0.0';
    final build = r['build_number'] ?? '1';
    final minVer = r['min_supported_version'] ?? '1.0.0';
    final minBuild = r['min_supported_build'] ?? '1';
    final title = r['title'] ?? 'Release';
    final updateType = r['update_type']?.toString() ?? 'optional';
    final status = r['status']?.toString() ?? 'draft';
    final isActive = r['is_active'] == true;
    final isMandatory = updateType == 'mandatory';
    final isPublished = status == 'published';
    final downloadUrl = r['download_url']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppUi.accentGreen.withValues(alpha: 0.5) : AppUi.borderOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'v$version (Build $build)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppUi.accentGreen.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppUi.accentGreen),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isPublished ? AppUi.bluePrimary : Colors.amber).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isPublished ? AppUi.bluePrimary : Colors.amber.shade800,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isMandatory ? AppUi.error : Colors.teal).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isMandatory ? 'MANDATORY' : 'OPTIONAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isMandatory ? AppUi.error : Colors.teal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            'Requires >= v$minVer+$minBuild',
            style: TextStyle(
              fontSize: 12,
              color: isMandatory ? AppUi.error : AppUi.textSecondaryOf(context),
            ),
          ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  downloadUrl,
                  style: const TextStyle(fontSize: 11, color: AppUi.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isPublished) ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppUi.accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => _confirmPublish(r),
                  child: const Text('Publish', style: TextStyle(fontSize: 12)),
                ),
              ] else if (!isActive) ...[
                OutlinedButton(
                  onPressed: () => _confirmPublish(r),
                  child: const Text('Set Active', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPublish(Map<String, dynamic> r) async {
    AppHaptics.medium();
    final isMandatory = r['update_type'] == 'mandatory';
    final version = r['version'];
    final minVer = r['min_supported_version'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isMandatory ? Icons.warning_rounded : Icons.send_rounded,
              color: isMandatory ? AppUi.error : AppUi.bluePrimary,
            ),
            const SizedBox(width: 10),
            const Text('Publish Release'),
          ],
        ),
        content: Text(
          isMandatory
              ? 'Warning: Publishing version $version as MANDATORY will lock out all devices running older than v$minVer until they update.'
              : 'Publish version $version to production as active release?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isMandatory ? AppUi.error : AppUi.bluePrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _supabase.rpc('publish_app_release', params: {'p_release_id': r['id']});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Version $version published!')),
        );
        _loadReleases();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publish error: $e'), backgroundColor: AppUi.error),
        );
      }
    }
  }

  Future<void> _openCreateReleaseDialog() async {
    final versionCtl = TextEditingController(text: '1.0.1');
    final buildCtl = TextEditingController(text: '2');
    final minVerCtl = TextEditingController(text: '1.0.0');
    final minBuildCtl = TextEditingController(text: '1');
    final titleCtl = TextEditingController(text: 'eRefill System Update');
    final notesCtl = TextEditingController(text: '- Delivery fee improvements\n- Security patch');
    String updateType = 'optional';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: const Text('New Release Draft'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: versionCtl,
                          decoration: const InputDecoration(labelText: 'Version (e.g. 1.0.1)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: buildCtl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Build No.'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minVerCtl,
                          decoration: const InputDecoration(labelText: 'Min Version'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: minBuildCtl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Min Build'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: updateType,
                    decoration: const InputDecoration(labelText: 'Update Type'),
                    items: const [
                      DropdownMenuItem(value: 'optional', child: Text('Optional')),
                      DropdownMenuItem(value: 'mandatory', child: Text('Mandatory Lockout')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDlgState(() => updateType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtl,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Release Notes'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create Draft'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && mounted) {
      try {
        await _supabase.from('app_releases').insert({
          'platform': 'android',
          'channel': 'official_apk',
          'version': versionCtl.text.trim(),
          'build_number': int.tryParse(buildCtl.text.trim()) ?? 1,
          'min_supported_version': minVerCtl.text.trim(),
          'min_supported_build': int.tryParse(minBuildCtl.text.trim()) ?? 1,
          'title': titleCtl.text.trim(),
          'release_notes': notesCtl.text.trim(),
          'update_type': updateType,
          'status': 'draft',
          'is_active': false,
          'download_url': 'https://erefill-landing.pages.dev/downloads/eRefill.apk',
        });
        if (!mounted) return;
        _loadReleases();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create draft: $e'), backgroundColor: AppUi.error),
        );
      }
    }
  }

  void _showAuditLogs(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppUi.surfaceOf(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtl) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _supabase
                .from('app_release_audit_logs')
                .select('*')
                .order('created_at', ascending: false)
                .limit(40)
                .then((rows) => List<Map<String, dynamic>>.from(rows)),
            builder: (context, snapshot) {
              final logs = snapshot.data ?? [];
              return ListView(
                controller: scrollCtl,
                padding: const EdgeInsets.all(20),
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
                  const Text('Release Audit Trail', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (logs.isEmpty)
                    const Center(child: Text('No audit logs yet.'))
                  else
                    ...logs.map((log) {
                      final action = log['action']?.toString() ?? 'ACTION';
                      final email = log['admin_email']?.toString() ?? 'Admin';
                      final time = log['created_at'] != null
                          ? DateFormat('MMM d, HH:mm').format(DateTime.parse(log['created_at'].toString()))
                          : '';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('$action by $email', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: Text(log['details']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
                        trailing: Text(time, style: const TextStyle(fontSize: 11, color: AppUi.textMuted)),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showPreviewOptions(BuildContext context, Map<String, dynamic>? active) {
    final policy = AppUpdatePolicy.preview(
      latestVersion: active?['version']?.toString() ?? '1.1.0',
      latestBuild: active != null ? (active['build_number'] as num).toInt() : 2,
      minSupportedVersion: active?['min_supported_version']?.toString() ?? '1.0.0',
      minSupportedBuild: active != null ? (active['min_supported_build'] as num).toInt() : 1,
      title: active?['title']?.toString() ?? 'Security & Version Update',
      releaseNotes: active?['release_notes']?.toString() ?? '- Critical security patch\n- Real-time updates',
      downloadUrl: active?['download_url']?.toString() ?? 'https://erefill-landing.pages.dev/downloads/eRefill.apk',
      checksumSha256: active?['checksum_sha256']?.toString(),
      isMandatory: (active?['update_type']?.toString() ?? 'mandatory') == 'mandatory',
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppUi.surfaceOf(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Preview Update UI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.shield_rounded, color: AppUi.error),
                title: const Text('Preview Mandatory Update Screen'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Mandatory Update Preview'),
                          leading: IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        body: const MandatoryUpdateScreen(),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_rounded, color: AppUi.bluePrimary),
                title: const Text('Preview Optional Update Dialog'),
                onTap: () {
                  Navigator.pop(ctx);
                  OptionalUpdateDialog.show(context, policy);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
