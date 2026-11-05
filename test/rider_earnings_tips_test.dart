import 'package:erefill/core/sync/sync_resources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sumAmounts tolerates numbers, strings and nulls', () {
    expect(
      RiderDashboardData.sumAmounts([
        {'tip_amount': 20},
        {'tip_amount': '15.5'},
        {'tip_amount': null},
        'junk',
      ], 'tip_amount'),
      35.5,
    );
  });

  test('tips survive the cache round trip and old caches default to 0', () {
    const data = RiderDashboardData(
      profile: null,
      activeOrders: [],
      completedDeliveries: 2,
      totalEarnings: 90,
      totalTips: 30,
    );
    expect(RiderDashboardData.fromJson(data.toJson()).totalTips, 30);
    expect(
      RiderDashboardData.fromJson({'completed': 1, 'earnings': 10}).totalTips,
      0,
    );
  });
}
