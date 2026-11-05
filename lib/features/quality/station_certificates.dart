import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';

/// A water-quality lab test or permit uploaded by a station.
class StationCert {
  const StationCert({
    required this.id,
    required this.type,
    required this.issuedOn,
    required this.expiresOn,
    required this.status,
    required this.filePath,
    this.rejectionReason,
  });

  final String id;

  /// bacteriological | physical_chemical | sanitary_permit | business_permit
  final String type;
  final DateTime issuedOn;
  final DateTime expiresOn;

  /// pending | approved | rejected | expired
  final String status;
  final String filePath;
  final String? rejectionReason;

  static const types = <String, String>{
    'bacteriological': 'Bacteriological water test',
    'physical_chemical': 'Physical & chemical water test',
    'sanitary_permit': 'Sanitary permit',
    'business_permit': 'Business permit',
  };

  static const labTests = {'bacteriological', 'physical_chemical'};

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  bool isValidOn(DateTime day) =>
      status == 'approved' && expiresOn.isAfter(day);

  /// "Water tested · Oct 2026" from the newest valid approved lab test.
  static String? badgeLabel(List<StationCert> certs, DateTime today) {
    final valid = certs
        .where((c) => labTests.contains(c.type) && c.isValidOn(today))
        .toList()
      ..sort((a, b) => b.issuedOn.compareTo(a.issuedOn));
    return valid.isEmpty ? null : 'Water tested · ${monthYear(valid.first.issuedOn)}';
  }

  factory StationCert.fromRow(Map<String, dynamic> r) => StationCert(
        id: r['id'].toString(),
        type: r['cert_type'].toString(),
        issuedOn: DateTime.parse(r['issued_on'].toString()),
        expiresOn: DateTime.parse(r['expires_on'].toString()),
        status: r['status'].toString(),
        filePath: r['file_path'].toString(),
        rejectionReason: r['rejection_reason']?.toString(),
      );
}

abstract interface class CertificateRepository {
  Future<List<StationCert>> forStation(String ownerId);
  Future<String> uploadFile(List<int> bytes, String ext);
  Future<void> submit(String type, DateTime issued, DateTime expires, String path);
  Future<Uri?> fileUrl(String path);
}

class SupabaseCertificateRepository implements CertificateRepository {
  SupabaseCertificateRepository([SupabaseClient? c])
      : _db = c ?? Supabase.instance.client;
  final SupabaseClient _db;

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<StationCert>> forStation(String ownerId) async {
    final rows = await _db
        .from('station_certifications')
        .select('id, cert_type, issued_on, expires_on, status, file_path, rejection_reason')
        .eq('owner_id', ownerId)
        .order('issued_on', ascending: false);
    return [for (final r in rows) StationCert.fromRow(r)];
  }

  @override
  Future<String> uploadFile(List<int> bytes, String ext) async {
    final uid = _db.auth.currentUser!.id;
    final path = '$uid/certs/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('verification_docs').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext',
          ),
        );
    return path;
  }

  @override
  Future<void> submit(String type, DateTime issued, DateTime expires, String path) =>
      _db.rpc('submit_station_certification', params: {
        'p_cert_type': type,
        'p_issued_on': _date(issued),
        'p_expires_on': _date(expires),
        'p_file_path': path,
      });

  @override
  Future<Uri?> fileUrl(String path) async => Uri.tryParse(
        await _db.storage.from('verification_docs').createSignedUrl(path, 600),
      );
}

typedef FilePick = Future<(List<int>, String)?> Function();

Future<(List<int>, String)?> _pickPhoto() async {
  final f = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  );
  if (f == null) return null;
  return (await f.readAsBytes(), f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg');
}

/// Owner screen: upload lab tests and permits, see review status.
class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({
    super.key,
    required this.ownerId,
    this.repository,
    this.pickFile,
    this.today,
  });

  final String ownerId;
  final CertificateRepository? repository;
  final FilePick? pickFile;
  final DateTime Function()? today;

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  late final CertificateRepository _repo =
      widget.repository ?? SupabaseCertificateRepository();
  List<StationCert>? _certs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _repo.forStation(widget.ownerId);
      if (mounted) setState(() => _certs = c);
    } catch (_) {
      if (mounted) setState(() => _certs = const []);
    }
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CertForm(
        repo: _repo,
        pickFile: widget.pickFile ?? _pickPhoto,
        today: (widget.today ?? DateTime.now)(),
      ),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final certs = _certs;
    return Scaffold(
      appBar: AppBar(title: const Text('Water quality certificates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Add certificate'),
      ),
      body: certs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  'Upload your latest water analysis and permits. Approved, '
                  'unexpired lab tests show customers a "Water tested" badge.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (certs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: Center(child: Text('No certificates yet.')),
                  ),
                for (final c in certs)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.science_outlined),
                      title: Text(StationCert.types[c.type] ?? c.type),
                      subtitle: Text(
                        'Valid until ${StationCert.monthYear(c.expiresOn)} · '
                        '${switch (c.status) {
                          'approved' => 'Approved',
                          'pending' => 'Waiting for review',
                          'expired' => 'Expired',
                          _ => 'Rejected: ${c.rejectionReason ?? ''}',
                        }}',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CertForm extends StatefulWidget {
  const _CertForm({required this.repo, required this.pickFile, required this.today});
  final CertificateRepository repo;
  final FilePick pickFile;
  final DateTime today;

  @override
  State<_CertForm> createState() => _CertFormState();
}

class _CertFormState extends State<_CertForm> {
  String _type = 'bacteriological';
  late DateTime _issued = widget.today;
  late DateTime _expires = DateTime(widget.today.year, widget.today.month + 6, widget.today.day);
  String? _path;
  bool _busy = false;
  String? _error;

  Future<void> _pickDate(bool issued) async {
    final d = await showDatePicker(
      context: context,
      initialDate: issued ? _issued : _expires,
      firstDate: DateTime(widget.today.year - 3),
      lastDate: DateTime(widget.today.year + 5),
    );
    if (d != null) setState(() => issued ? _issued = d : _expires = d);
  }

  Future<void> _attach() async {
    final f = await widget.pickFile();
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final p = await widget.repo.uploadFile(f.$1, f.$2);
      if (mounted) setState(() => _path = p);
    } catch (_) {
      if (mounted) setState(() => _error = 'Upload failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) => setState(() {
        _busy = false;
        _error = message;
      });

  Future<void> _submit() async {
    if (_path == null) {
      setState(() => _error = 'Attach a photo of the certificate.');
      return;
    }
    if (!_expires.isAfter(_issued)) {
      setState(() => _error = 'Expiry must be after the issue date.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.submit(_type, _issued, _expires, _path!);
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) _fail(e.message);
    } catch (_) {
      if (mounted) _fail('Submitting failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New certificate', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: [
              for (final e in StationCert.types.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Issued on'),
            trailing: Text(StationCert.monthYear(_issued)),
            onTap: () => _pickDate(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Valid until'),
            trailing: Text(StationCert.monthYear(_expires)),
            onTap: () => _pickDate(false),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _attach,
            icon: Icon(_path == null ? Icons.attach_file_rounded : Icons.check_rounded),
            label: Text(_path == null ? 'Attach file' : 'File attached'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Submit')),
        ],
      ),
    );
  }
}

/// Customer-facing water quality section on a station page.
class StationQualitySection extends StatefulWidget {
  const StationQualitySection({super.key, required this.stationId, this.repository});
  final String stationId;
  final CertificateRepository? repository;

  @override
  State<StationQualitySection> createState() => _StationQualitySectionState();
}

class _StationQualitySectionState extends State<StationQualitySection> {
  late final CertificateRepository _repo =
      widget.repository ?? SupabaseCertificateRepository();
  List<StationCert> _certs = const [];

  @override
  void initState() {
    super.initState();
    _repo.forStation(widget.stationId).then(
      (c) {
        if (mounted) setState(() => _certs = c.where((x) => x.status == 'approved').toList());
      },
      onError: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final valid = _certs.where((c) => c.isValidOn(today)).toList();
    if (valid.isEmpty) return const SizedBox.shrink();
    final badge = StationCert.badgeLabel(valid, today);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: AppColors.uiSuccess),
              const SizedBox(width: 8),
              Text(badge ?? 'Permits on file', style: theme.textTheme.titleSmall),
            ],
          ),
          for (final c in valid)
            TextButton(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () async {
                final url = await _repo.fileUrl(c.filePath);
                if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
              },
              child: Text(
                '${StationCert.types[c.type] ?? c.type} · valid until ${StationCert.monthYear(c.expiresOn)}',
              ),
            ),
        ],
      ),
    );
  }
}
