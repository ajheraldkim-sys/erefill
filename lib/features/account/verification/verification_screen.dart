import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import 'id_checks.dart';
import 'id_photo_analyzer.dart';
import 'liveness_screen.dart';

/// Where the signed-in user stands with ID verification.
class VerificationState {
  const VerificationState({
    required this.status,
    required this.isOwner,
    this.rejectionReason,
    this.profileName = '',
  });

  /// 'unverified' | 'pending' | 'approved' | 'rejected'
  final String status;
  final bool isOwner;
  final String? rejectionReason;

  /// Name on the account, compared with the name read from the ID.
  final String profileName;

  bool get canSubmit => status == 'unverified' || status == 'rejected';
}

abstract interface class VerificationRepository {
  Future<VerificationState> load();

  /// Uploads one photo to the user's private folder; returns its storage path.
  Future<String> upload(String slot, Uint8List bytes, String ext);

  Future<void> submit({
    required String idType,
    required String last4,
    required String front,
    String? back,
    required String selfie,
    String? permit,
    Map<String, dynamic>? checks,
  });
}

class SupabaseVerificationRepository implements VerificationRepository {
  SupabaseVerificationRepository([SupabaseClient? client])
    : _db = client ?? Supabase.instance.client;
  final SupabaseClient _db;
  static const bucket = 'verification_docs';

  String get _uid => _db.auth.currentUser!.id;

  @override
  Future<VerificationState> load() async {
    final profile = await _db
        .from('profiles')
        .select('role, verification_status, full_name, first_name, last_name')
        .eq('id', _uid)
        .single();
    String? reason;
    final status = profile['verification_status']?.toString() ?? 'unverified';
    if (status == 'rejected') {
      final last = await _db
          .from('identity_verifications')
          .select('rejection_reason')
          .eq('user_id', _uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      reason = last?['rejection_reason']?.toString();
    }
    return VerificationState(
      status: status,
      isOwner: profile['role'] == 'owner',
      rejectionReason: reason,
      profileName: _name(profile),
    );
  }

  static String _name(Map<String, dynamic> p) {
    final full = p['full_name']?.toString().trim() ?? '';
    if (full.isNotEmpty && full != 'New User') return full;
    return '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
  }

  @override
  Future<String> upload(String slot, Uint8List bytes, String ext) async {
    final path = '$_uid/${DateTime.now().millisecondsSinceEpoch}_$slot.$ext';
    await _db.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext',
          ),
        );
    return path;
  }

  @override
  Future<void> submit({
    required String idType,
    required String last4,
    required String front,
    String? back,
    required String selfie,
    String? permit,
    Map<String, dynamic>? checks,
  }) async {
    final params = {
      'p_id_type': idType,
      'p_id_number_last4': last4,
      'p_front_path': front,
      'p_back_path': back,
      'p_selfie_path': selfie,
      'p_business_permit_path': permit,
    };
    try {
      await _db.rpc(
        'submit_identity_verification',
        params: {...params, 'p_auto_checks': ?checks},
      );
    } on PostgrestException catch (e) {
      // Database not yet updated (identity_verification_checks.sql): the
      // function has no p_auto_checks yet. Submit the photos without checks.
      if (checks == null || e.code != 'PGRST202') rethrow;
      await _db.rpc('submit_identity_verification', params: params);
    }
  }
}

typedef ImagePick = Future<(Uint8List, String)?> Function(ImageSource source);

Future<(Uint8List, String)?> _defaultPick(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1800,
    imageQuality: 82,
  );
  if (file == null) return null;
  final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
  return (await file.readAsBytes(), ext);
}

typedef LiveSelfieCapture = Future<LiveSelfie?> Function(BuildContext context);

Future<LiveSelfie?> _defaultLiveSelfie(BuildContext context) => Navigator.of(
  context,
).push<LiveSelfie>(MaterialPageRoute(builder: (_) => const LivenessScreen()));

/// ID verification for customers and station owners. Helps prevent scam
/// orders and fake stations.
///
/// Free on-device checks (Google ML Kit): reads the ID, finds the photo and
/// the National ID QR, and takes a live selfie. Results go to the admin
/// with the photos; an admin still makes the decision.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    this.repository,
    this.pickImage,
    this.analyzer,
    this.liveSelfie,
  });

  final VerificationRepository? repository;
  final ImagePick? pickImage;
  final IdPhotoAnalyzer? analyzer;
  final LiveSelfieCapture? liveSelfie;

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final VerificationRepository _repo =
      widget.repository ?? SupabaseVerificationRepository();
  late final ImagePick _pick = widget.pickImage ?? _defaultPick;
  late final IdPhotoAnalyzer _analyzer =
      widget.analyzer ?? MlKitIdPhotoAnalyzer();
  late final LiveSelfieCapture _liveSelfie =
      widget.liveSelfie ?? _defaultLiveSelfie;
  final _last4 = TextEditingController();

  static const _idTypes = <String, String>{
    'philsys': 'PhilSys National ID',
    'drivers_license': "Driver's license",
    'umid': 'UMID',
    'passport': 'Passport',
    'postal': 'Postal ID',
    'voters': "Voter's ID",
    'prc': 'PRC ID',
    'other': 'Other government ID',
  };

  VerificationState? _state;
  String _idType = 'philsys';
  final Map<String, String> _paths = {};
  final Set<String> _uploading = {};
  final Map<String, IdPhotoScan> _scans = {};
  final Set<String> _scanFailed = {};
  LivenessResult? _liveness;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _last4.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.load();
      if (mounted) setState(() => _state = s);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not load your verification status.');
      }
    }
  }

  Future<void> _add(String slot, {bool plainSelfie = false}) async {
    (Uint8List, String)? picked;
    if (slot == 'selfie' && !plainSelfie) {
      final live = await _liveSelfie(context);
      if (live == null) return;
      _liveness = live.result;
      picked = (live.bytes, 'jpeg');
    } else {
      picked = await _pick(
        slot == 'selfie' ? ImageSource.camera : ImageSource.gallery,
      );
      if (picked == null) return;
      if (slot == 'selfie') _liveness = null;
    }
    if (!mounted) return;
    if (slot == 'front' || slot == 'back') _scan(slot, picked.$1, picked.$2);
    setState(() => _uploading.add(slot));
    try {
      final path = await _repo.upload(slot, picked.$1, picked.$2);
      if (mounted) setState(() => _paths[slot] = path);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Upload failed. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _uploading.remove(slot));
    }
  }

  Future<void> _scan(String slot, Uint8List bytes, String ext) async {
    try {
      final scan = await _analyzer.analyze(bytes, ext);
      if (!mounted) return;
      setState(() {
        _scans[slot] = scan;
        _scanFailed.remove(slot);
      });
    } catch (e) {
      debugPrint('ID photo check failed: $e');
      if (mounted) setState(() => _scanFailed.add(slot));
    }
  }

  IdCheckReport? get _report {
    if (!_scans.containsKey('front')) return null;
    final scans = _scans.values;
    return IdChecks.evaluate(
      IdCheckInput(
        profileName: _state?.profileName ?? '',
        last4: _last4.text,
        idType: _idType,
        ocrText: scans.map((s) => s.text).join('\n'),
        qrValues: [for (final s in scans) ...s.codes],
        facesOnId: _scans['front']?.faces ?? 0,
        liveness: _liveness,
      ),
    );
  }

  bool get _ready =>
      _paths.containsKey('front') &&
      _paths.containsKey('selfie') &&
      (!(_state?.isOwner ?? false) || _paths.containsKey('permit'));

  Future<void> _submit() async {
    if (!_ready) {
      setState(
        () => _error = _state!.isOwner
            ? 'Add the front of your ID, a selfie and your permit.'
            : 'Add the front of your ID and a selfie.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _repo.submit(
        idType: _idType,
        last4: _last4.text.trim(),
        front: _paths['front']!,
        back: _paths['back'],
        selfie: _paths['selfie']!,
        permit: _paths['permit'],
        checks: {
          ...?_report?.toJson(),
          'checked_on_device': _report != null,
          if (_scanFailed.isNotEmpty) 'scan_failed': _scanFailed.toList(),
        },
      );
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Submitting failed. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('ID verification')),
      body: s == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statusCard(context, s),
                  if (s.canSubmit) ..._form(context, s),
                ],
              ),
            ),
    );
  }

  Widget _statusCard(BuildContext context, VerificationState s) {
    final theme = Theme.of(context);
    final (icon, color, title, body) = switch (s.status) {
      'approved' => (
        Icons.verified_rounded,
        AppColors.uiSuccess,
        'Your ID is verified',
        s.isOwner
            ? 'Customers see a Verified badge on your station.'
            : 'Thanks! Cash-on-delivery limits are lifted.',
      ),
      'pending' => (
        Icons.hourglass_top_rounded,
        AppColors.uiWarning,
        'Your ID is being reviewed',
        'This usually takes less than a day. We will notify you.',
      ),
      'rejected' => (
        Icons.error_outline_rounded,
        AppColors.uiError,
        'Please try again',
        'Reason: ${s.rejectionReason ?? 'The photos could not be verified.'}',
      ),
      _ => (
        Icons.badge_outlined,
        AppUi.brandOf(context),
        'Verify your identity',
        s.isOwner
            ? 'Stations must be verified before they can receive orders.'
            : 'Verified customers can place larger cash-on-delivery orders. '
                  'It helps riders and stations trust every order.',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _form(BuildContext context, VerificationState s) {
    final theme = Theme.of(context);
    Widget slot(
      String key,
      String label,
      IconData icon, {
      bool optional = false,
    }) {
      final done = _paths.containsKey(key);
      final busy = _uploading.contains(key);
      return Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(
            busy
                ? 'Uploading…'
                : done
                ? 'Added'
                : optional
                ? 'Optional'
                : 'Required',
          ),
          trailing: done
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.uiSuccess,
                )
              : const Icon(Icons.add_a_photo_outlined),
          onTap: busy ? null : () => _add(key),
        ),
      );
    }

    return [
      const SizedBox(height: 20),
      Text('Type of ID', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _idType,
        items: [
          for (final e in _idTypes.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() => _idType = v ?? _idType),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('id-last4'),
        controller: _last4,
        maxLength: 4,
        decoration: const InputDecoration(
          labelText: 'Last 4 characters of the ID number',
          helperText: 'We only keep the last 4 characters.',
        ),
      ),
      const SizedBox(height: 8),
      slot('front', 'Front of ID', Icons.credit_card_rounded),
      slot('back', 'Back of ID', Icons.flip_rounded, optional: true),
      slot(
        'selfie',
        'Live selfie holding your ID',
        Icons.face_retouching_natural_rounded,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _uploading.contains('selfie')
              ? null
              : () => _add('selfie', plainSelfie: true),
          child: const Text("Live selfie not working? Take a normal photo"),
        ),
      ),
      if (s.isOwner)
        slot(
          'permit',
          'Business or sanitary permit',
          Icons.description_outlined,
        ),
      ..._quickCheck(context),
      const SizedBox(height: 8),
      Text(
        'Your photos are private: only you and eRefill admins can see them.',
        style: theme.textTheme.bodySmall,
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(_submitting ? 'Submitting…' : 'Submit for review'),
      ),
    ];
  }

  /// Friendly, non-blocking hints so users can retake a bad photo before an
  /// admin has to reject it.
  List<Widget> _quickCheck(BuildContext context) {
    final r = _report;
    final hints = <String>[
      if (_scanFailed.contains('front'))
        "We couldn't check your ID photo, but you can still submit it.",
      if (r != null && r.nameMatch < IdChecks.nameThreshold)
        "We couldn't read your name on the ID. Retake it in good light, "
            'without glare, or check that your profile name matches your ID.',
      if (r != null && !r.faceOnId)
        "We couldn't see the photo on your ID. Make sure the whole card is in the picture.",
      if (r != null && r.idTypeMatches == false)
        'This does not look like the ID type you chose above.',
      if (r != null && r.idType == 'philsys' && !r.qrFound)
        "We couldn't read the National ID QR code. Make sure it is sharp and not covered.",
      if (r != null && r.last4Found == false)
        'The last 4 characters you typed were not found on the ID.',
      if (_liveness != null && !_liveness!.passed)
        'The live selfie did not finish. Try it again.',
    ];
    final ok = r != null && hints.isEmpty;
    if (r == null && hints.isEmpty) return const [];
    final color = ok ? AppColors.uiSuccess : AppColors.uiWarning;
    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  'Quick check',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (ok)
              const Text(
                'Your ID photo looks clear. This check ran on your phone.',
              ),
            for (final h in hints)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $h'),
              ),
          ],
        ),
      ),
    ];
  }
}
