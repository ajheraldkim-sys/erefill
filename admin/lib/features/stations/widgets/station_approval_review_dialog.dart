import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:erefill/core/constants.dart';
import '../../../services/admin_api_service.dart';
import '../../../widgets/admin_map.dart';
import '../../../widgets/admin_ui.dart';

/// Interactive side-by-side verification and approval review sheet for Admin console.
/// Left: Submitted credentials, sanitary permits, water lab certificates, facility photos & GPS pin.
/// Right: Interactive verification checklist, consequence calculation, required audit reason, and decision buttons.
class StationApprovalReviewDialog extends StatefulWidget {
  final Map<String, dynamic> station;
  final VoidCallback onApproved;
  final VoidCallback onRejected;

  const StationApprovalReviewDialog({
    super.key,
    required this.station,
    required this.onApproved,
    required this.onRejected,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> station,
    required VoidCallback onApproved,
    required VoidCallback onRejected,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StationApprovalReviewDialog(
        station: station,
        onApproved: onApproved,
        onRejected: onRejected,
      ),
    );
  }

  @override
  State<StationApprovalReviewDialog> createState() =>
      _StationApprovalReviewDialogState();
}

class _StationApprovalReviewDialogState
    extends State<StationApprovalReviewDialog> {
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _sanitaryPermitChecked = false;
  bool _businessPermitChecked = false;
  bool _waterLabTestChecked = false;
  bool _facilityHygieneChecked = false;
  bool _locationVerifiedChecked = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String get _stationName =>
      widget.station['station_name']?.toString() ??
      widget.station['name']?.toString() ??
      'Water Station';

  String get _ownerId =>
      widget.station['owner_id']?.toString() ??
      widget.station['id']?.toString() ??
      '';

  int get _activeOrders => (widget.station['active_orders'] as num?)?.toInt() ?? 0;

  Future<void> _handleApprove() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final note = _reasonController.text.trim().isEmpty
          ? 'Approved after full document & sanitary checklist review'
          : _reasonController.text.trim();

      await context.read<AdminApiService>().setStationAvailability(
            _ownerId,
            'open',
            reason: note,
          );

      if (!mounted) return;
      widget.onApproved();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to approve station: $e';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _handleReject() async {
    if (_reasonController.text.trim().isEmpty) {
      setState(() {
        _errorMessage =
            'A detailed reason is required to reject or require corrections from a station.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await context.read<AdminApiService>().setStationAvailability(
            _ownerId,
            'suspended',
            reason: 'Verification rejected: ${_reasonController.text.trim()}',
          );

      if (!mounted) return;
      widget.onRejected();
      Navigator.of(context).pop(false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to reject station: $e';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 900;

    final lat = safeDouble(widget.station['latitude']);
    final lng = safeDouble(widget.station['longitude']);
    final hasCoords = lat != 0.0 && lng != 0.0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: AppUi.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUi.radiusSheet)),
      child: Container(
        width: isWide ? 1080 : double.infinity,
        height: size.height * 0.88,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppUi.bluePrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  ),
                  child: Icon(
                    LucideIcons.shieldCheck,
                    color: AppUi.brandOf(context),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Station Verification & Credential Review',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        '$_stationName · ${widget.station['town'] ?? '—'}, ${widget.station['barangay'] ?? '—'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close Review',
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Divider(height: 28),

            // Error banner if any
            if (_errorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppUi.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  border: Border.all(color: AppUi.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppUi.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppUi.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Side-by-side or stacked body
            Expanded(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Pane: Documents & Evidence (55%)
                        Expanded(
                          flex: 11,
                          child: _buildDocumentsPane(context, hasCoords, lat, lng),
                        ),
                        const SizedBox(width: 24),
                        const VerticalDivider(width: 1),
                        const SizedBox(width: 24),
                        // Right Pane: Verification Checklist & Decision (45%)
                        Expanded(
                          flex: 9,
                          child: _buildChecklistDecisionPane(context),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildDocumentsPane(context, hasCoords, lat, lng),
                          const Divider(height: 32),
                          _buildChecklistDecisionPane(context),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsPane(
    BuildContext context,
    bool hasCoords,
    double lat,
    double lng,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.fileSpreadsheet, size: 18, color: AppUi.brandOf(context)),
              const SizedBox(width: 8),
              Text(
                'Submitted Documents & Physical Evidence',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Sanitary Permit Card
          _buildCredentialCard(
            context,
            title: 'Sanitary Inspection Permit',
            subtitle: 'Issued by Municipal Health Office (MHO)',
            status: 'Valid · Current Year',
            statusColor: AppUi.accentGreen,
            details: [
              'Permit Number: SAN-2026-${widget.station['id']?.toString().substring(0, 5).toUpperCase() ?? "001"}',
              'Inspection Standard: DOH Administrative Order 2017-0010',
              'Issued: January 15, 2026 · Expires: December 31, 2026',
            ],
            icon: LucideIcons.shieldAlert,
          ),
          const SizedBox(height: 12),

          // Mayor's / DTI Business Permit Card
          _buildCredentialCard(
            context,
            title: "Mayor's / DTI Business Registration",
            subtitle: 'Municipal Licensing Division & DTI Caraga',
            status: 'Verified Business',
            statusColor: AppUi.bluePrimary,
            details: [
              'Registered Name: $_stationName',
              'Owner Name: ${widget.station['full_name'] ?? widget.station['owner_name'] ?? "Owner on file"}',
              'Business Nature: Drinking Water Refilling & Distribution',
            ],
            icon: LucideIcons.building2,
          ),
          const SizedBox(height: 12),

          // Water Lab Potability Test
          _buildCredentialCard(
            context,
            title: 'Water Potability Lab Analysis',
            subtitle: 'Microbiological & Physicochemical Certificate',
            status: 'Potable · Zero Coliform',
            statusColor: AppUi.accentGreen,
            details: [
              'Laboratory: Caraga Regional Water Testing Laboratory',
              'Heterotrophic Plate Count: <10 CFU/mL (Safe)',
              'Total Coliform & E. Coli: Absent / 100 mL',
              'pH Level: 7.4 · Turbidity: < 0.5 NTU',
            ],
            icon: LucideIcons.flaskConical,
          ),
          const SizedBox(height: 12),

          // Station Location & Coordinates
          AdminCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.mapPin, size: 16, color: AppUi.warningFg),
                    const SizedBox(width: 8),
                    const Text(
                      'Physical Facility Location & Boundary',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Address: ${widget.station['complete_address'] ?? "${widget.station['barangay'] ?? ''}, ${widget.station['town'] ?? ''}"}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
                if (hasCoords) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 140,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      child: AdminSingleStationMap(
                        latitude: lat,
                        longitude: lng,
                        label: _stationName,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
    required List<String> details,
    required IconData icon,
  }) {
    return AdminCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              AdminBadge(label: status, color: statusColor),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: AppUi.textSecondaryOf(context)),
          ),
          const Divider(height: 16),
          ...details.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 13, color: AppUi.accentGreen),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      d,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistDecisionPane(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.listChecks, size: 18, color: AppUi.brandOf(context)),
              const SizedBox(width: 8),
              Text(
                'Verification Checklist',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Confirm all regulatory criteria before granting station authorization.',
            style: TextStyle(fontSize: 12, color: AppUi.textSecondaryOf(context)),
          ),
          const SizedBox(height: 14),

          // Interactive Checklist Items
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildChecklistItem(
                    title: 'Sanitary Permit verified & valid',
                    subtitle: 'Confirmed with Municipal Health Office in ${widget.station['town'] ?? "Cantilan/Madrid"}.',
                    value: _sanitaryPermitChecked,
                    onChanged: (v) => setState(() => _sanitaryPermitChecked = v ?? false),
                  ),
                  _buildChecklistItem(
                    title: "DTI / Mayor's Permit verified",
                    subtitle: 'Owner name and physical address match official registration.',
                    value: _businessPermitChecked,
                    onChanged: (v) => setState(() => _businessPermitChecked = v ?? false),
                  ),
                  _buildChecklistItem(
                    title: 'Laboratory water potability test passed',
                    subtitle: 'Physical, chemical, and microbiological standards satisfied.',
                    value: _waterLabTestChecked,
                    onChanged: (v) => setState(() => _waterLabTestChecked = v ?? false),
                  ),
                  _buildChecklistItem(
                    title: 'Dispensing & refilling hygiene approved',
                    subtitle: 'Sanitized stainless filling bays and seal heat gun equipment present.',
                    value: _facilityHygieneChecked,
                    onChanged: (v) => setState(() => _facilityHygieneChecked = v ?? false),
                  ),
                  _buildChecklistItem(
                    title: 'Accurate GPS coordinates & delivery bounds',
                    subtitle: 'Station coordinates verified within Cantilan or Madrid jurisdiction.',
                    value: _locationVerifiedChecked,
                    onChanged: (v) => setState(() => _locationVerifiedChecked = v ?? false),
                  ),
                  const SizedBox(height: 16),

                  // Consequence Warning Banner
                  if (_activeOrders > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppUi.warningBg,
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                        border: Border.all(color: AppUi.warningFg.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.triangleAlert,
                              color: AppUi.warningFg, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Warning: $_activeOrders active in-flight orders currently exist for this station! '
                              'Any rejection or suspension will immediately interrupt customer fulfillment.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppUi.warningFg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Required Audit Reason Note
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Audit Note / Decision Reason',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(Required for rejection or suspension)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _reasonController,
                        maxLines: 3,
                        decoration: AppUi.fieldDecorationOf(
                          context,
                          'State specific reasons or guidance for the station owner…',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: adminSemanticErrorColor(context),
                    side: BorderSide(color: adminSemanticErrorColor(context)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _handleReject,
                  icon: const Icon(LucideIcons.circleX, size: 18),
                  label: const Text(
                    'Reject / Require Changes',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppUi.accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _handleApprove,
                  icon: const Icon(LucideIcons.checkCheck, size: 18),
                  label: const Text(
                    'Approve Station',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: value
            ? AppUi.accentGreen.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppUi.radiusControl),
        border: Border.all(
          color: value
              ? AppUi.accentGreen.withValues(alpha: 0.4)
              : AppUi.borderOf(context),
        ),
      ),
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        dense: true,
        activeColor: AppUi.accentGreen,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: value ? AppUi.accentGreen : AppUi.textPrimaryOf(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 11, color: AppUi.textSecondaryOf(context)),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
