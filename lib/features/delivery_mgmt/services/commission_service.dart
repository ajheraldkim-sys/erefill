/// Commission calculation service for the Delivery Management module.
///
/// Rules:
/// - Base commission = gallons * commissionPerGallon
/// - Milestone bonus: ₱50 for every 100-gallon milestone reached cumulatively
///   per rider per day (resets at midnight).
///
/// Example: Rider delivered 80 gallons before (today). New delivery = 30 gal.
///   → Now at 110 total. Crossed 100-gallon milestone → +₱50 bonus.
class CommissionService {
  static const double milestoneBonus = 50.0;
  static const double milestoneStep = 100.0;

  /// Calculate commission for a single delivery.
  ///
  /// [gallons]            — gallons in THIS delivery
  /// [commissionPerGallon] — rider's rate
  /// [previousGallonsToday] — gallons already delivered today by this rider
  ///   (before this delivery). Used to compute milestone crossings.
  static CommissionResult calculate({
    required double gallons,
    required double commissionPerGallon,
    double previousGallonsToday = 0,
  }) {
    final base = gallons * commissionPerGallon;

    final before = previousGallonsToday;
    final after = before + gallons;

    // Count how many 100-gallon milestones are newly crossed
    final milestonesBefore = (before / milestoneStep).floor();
    final milestonesAfter = (after / milestoneStep).floor();
    final newMilestones = milestonesAfter - milestonesBefore;

    final bonus = newMilestones * milestoneBonus;
    final total = base + bonus;

    return CommissionResult(
      base: base,
      bonus: bonus,
      total: total,
      newMilestones: newMilestones,
    );
  }
}

class CommissionResult {
  final double base;
  final double bonus;
  final double total;
  final int newMilestones;

  const CommissionResult({
    required this.base,
    required this.bonus,
    required this.total,
    required this.newMilestones,
  });

  @override
  String toString() =>
      'CommissionResult(base: $base, bonus: $bonus, total: $total, milestones: $newMilestones)';
}
