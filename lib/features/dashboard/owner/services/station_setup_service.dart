import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StationSectionStatus {
  final bool isComplete;
  final String title;
  final String statusText;
  final String? badgeText;

  const StationSectionStatus({
    required this.isComplete,
    required this.title,
    required this.statusText,
    this.badgeText,
  });
}

class StationSetupStatus {
  final bool isComplete;
  final int completedCount;
  final int totalSections;
  final int percentage;
  final bool eligibleToOpen;
  final String currentAvailability;
  final bool isOpen;
  final List<String> missingFields;

  final StationSectionStatus profileSection;
  final StationSectionStatus scheduleSection;
  final StationSectionStatus deliverySection;
  final StationSectionStatus productsSection;
  final StationSectionStatus paymentsSection;

  const StationSetupStatus({
    required this.isComplete,
    required this.completedCount,
    required this.totalSections,
    required this.percentage,
    required this.eligibleToOpen,
    required this.currentAvailability,
    required this.isOpen,
    required this.missingFields,
    required this.profileSection,
    required this.scheduleSection,
    required this.deliverySection,
    required this.productsSection,
    required this.paymentsSection,
  });

  bool get isProfileComplete => profileSection.isComplete;
  bool get isScheduleComplete => scheduleSection.isComplete;
  bool get isDeliveryComplete => deliverySection.isComplete;
  bool get isProductsComplete => productsSection.isComplete;
  bool get isPaymentsComplete => paymentsSection.isComplete;

  factory StationSetupStatus.empty() {
    return const StationSetupStatus(
      isComplete: false,
      completedCount: 0,
      totalSections: 5,
      percentage: 0,
      eligibleToOpen: false,
      currentAvailability: 'incomplete_setup',
      isOpen: false,
      missingFields: ['Station Profile', 'Operating Schedule', 'Delivery Rules', 'Products', 'Payment Methods'],
      profileSection: StationSectionStatus(
        isComplete: false,
        title: 'Station details',
        statusText: 'Add station details and map pin',
        badgeText: 'Required',
      ),
      scheduleSection: StationSectionStatus(
        isComplete: false,
        title: 'Operating schedule',
        statusText: 'Set opening hours and operating days',
        badgeText: 'Required',
      ),
      deliverySection: StationSectionStatus(
        isComplete: false,
        title: 'Pricing & delivery rules',
        statusText: 'Review delivery policy',
        badgeText: 'Required',
      ),
      productsSection: StationSectionStatus(
        isComplete: false,
        title: 'Water products & catalog',
        statusText: 'Add at least 1 orderable product',
        badgeText: 'Action needed',
      ),
      paymentsSection: StationSectionStatus(
        isComplete: false,
        title: 'Accepted payment methods',
        statusText: 'Select accepted payment methods',
        badgeText: 'Required',
      ),
    );
  }

  factory StationSetupStatus.fromRpc(Map<String, dynamic> data) {
    final isComplete = data['is_complete'] == true;
    final completedCount = (data['completed_count'] as num?)?.toInt() ?? 0;
    final totalSections = (data['total_sections'] as num?)?.toInt() ?? 5;
    final percentage = (data['percentage'] as num?)?.toInt() ?? 0;
    final eligibleToOpen = data['eligible_to_open'] == true;
    final currentAvailability = data['current_availability']?.toString() ?? 'closed';
    final isOpen = data['is_open'] == true;
    final missingFields = (data['missing_fields'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final sections = (data['sections'] as Map<String, dynamic>?) ?? {};

    final secProfile = sections['station_profile'] as Map<String, dynamic>?;
    final profileDone = secProfile?['complete'] == true;

    final secSchedule = sections['operating_schedule'] as Map<String, dynamic>?;
    final scheduleDone = secSchedule?['complete'] == true;

    final secDelivery = sections['delivery_rules'] as Map<String, dynamic>?;
    final deliveryDone = secDelivery?['complete'] == true;

    final secProducts = sections['products_pricing'] as Map<String, dynamic>?;
    final productsDone = secProducts?['complete'] == true;

    final secPayments = sections['payment_methods'] as Map<String, dynamic>?;
    final paymentsDone = secPayments?['complete'] == true;

    return StationSetupStatus(
      isComplete: isComplete,
      completedCount: completedCount,
      totalSections: totalSections,
      percentage: percentage,
      eligibleToOpen: eligibleToOpen,
      currentAvailability: currentAvailability,
      isOpen: isOpen,
      missingFields: missingFields,
      profileSection: StationSectionStatus(
        isComplete: profileDone,
        title: 'Station details',
        statusText: secProfile?['missing']?.toString() ??
            (profileDone ? 'Complete' : 'Missing details or map pin'),
        badgeText: profileDone ? 'Complete' : 'Required',
      ),
      scheduleSection: StationSectionStatus(
        isComplete: scheduleDone,
        title: 'Operating schedule',
        statusText: secSchedule?['missing']?.toString() ??
            (scheduleDone ? 'Complete' : 'Set opening hours and operating days'),
        badgeText: scheduleDone ? 'Complete' : 'Required',
      ),
      deliverySection: StationSectionStatus(
        isComplete: deliveryDone,
        title: 'Pricing & delivery rules',
        statusText: secDelivery?['missing']?.toString() ??
            (deliveryDone ? 'Complete' : 'Review delivery policy'),
        badgeText: deliveryDone ? 'Complete' : 'Required',
      ),
      productsSection: StationSectionStatus(
        isComplete: productsDone,
        title: 'Water products & catalog',
        statusText: secProducts?['missing']?.toString() ??
            (productsDone ? 'Complete' : 'Add at least 1 orderable product'),
        badgeText: productsDone ? 'Complete' : 'Action needed',
      ),
      paymentsSection: StationSectionStatus(
        isComplete: paymentsDone,
        title: 'Accepted payment methods',
        statusText: secPayments?['missing']?.toString() ??
            (paymentsDone ? 'Complete' : 'Select accepted payment methods'),
        badgeText: paymentsDone ? 'Complete' : 'Required',
      ),
    );
  }
}

class StationSetupService {
  final SupabaseClient _client;

  StationSetupService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<StationSetupStatus> getSetupStatus(String ownerId) async {
    try {
      final res = await _client.rpc(
        'check_station_setup_status',
        params: {'p_owner_id': ownerId},
      );
      if (res is Map) {
        return StationSetupStatus.fromRpc(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint('check_station_setup_status rpc error, evaluating locally: $e');
    }

    return evaluateLocally(ownerId: ownerId);
  }

  Future<StationSetupStatus> evaluateLocally({
    required String ownerId,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? settings,
    List<dynamic>? products,
  }) async {
    try {
      final prof = profile ??
          await _client
              .from('profiles')
              .select(
                'id, station_name, phone, town, barangay, complete_address, latitude, longitude, lat, lng, is_open, station_availability',
              )
              .eq('id', ownerId)
              .maybeSingle();

      Map<String, dynamic>? sett = settings;
      if (sett == null) {
        try {
          sett = await _client
              .from('owner_settings')
              .select(
                'owner_id, opening_time, closing_time, operating_days, delivery_ack, enabled_payment_methods, price_per_gallon',
              )
              .eq('owner_id', ownerId)
              .maybeSingle();
        } catch (e) {
          debugPrint('Notice: full owner_settings schema not available, fetching base columns: $e');
          try {
            sett = await _client
                .from('owner_settings')
                .select(
                  'owner_id, enabled_payment_methods, price_per_gallon',
                )
                .eq('owner_id', ownerId)
                .maybeSingle();
          } catch (e2) {
            debugPrint('Base owner_settings query fallback: $e2');
          }
        }
      }

      final prods = products ??
          await _client
              .from('products')
              .select('id, price, is_available')
              .eq('owner_id', ownerId)
              .eq('is_available', true)
              .gt('price', 0);

      final hasName = (prof?['station_name']?.toString().trim().isNotEmpty ?? false);
      final hasPhone = (prof?['phone']?.toString().trim().isNotEmpty ?? false);
      final hasTown = (prof?['town']?.toString().trim().isNotEmpty ?? false);
      final hasBrgy = (prof?['barangay']?.toString().trim().isNotEmpty ?? false);
      final lat = (prof?['latitude'] ?? prof?['lat']) as num?;
      final lng = (prof?['longitude'] ?? prof?['lng']) as num?;
      final hasCoords = lat != null && lng != null && lat != 0 && lng != 0;

      final isProfileComplete = hasName && hasPhone && hasTown && hasBrgy && hasCoords;

      final hasScheduleCols = sett != null &&
          (sett.containsKey('opening_time') || sett.containsKey('closing_time'));

      final bool isScheduleComplete;
      if (hasScheduleCols) {
        final opening = sett['opening_time']?.toString().trim();
        final closing = sett['closing_time']?.toString().trim();
        final days = sett['operating_days'];
        final hasDays = (days is List && days.isNotEmpty);
        isScheduleComplete = (opening != null && opening.isNotEmpty) &&
            (closing != null && closing.isNotEmpty) &&
            hasDays;
      } else {
        // Fallback for legacy DB schema before migration is applied
        isScheduleComplete = true;
      }

      final isDeliveryComplete = sett == null || sett['delivery_ack'] != false;

      final hasActiveProduct = (prods != null && prods.isNotEmpty) ||
          ((sett?['price_per_gallon'] as num?)?.toDouble() ?? 0) > 0;

      final enabledMethods = sett?['enabled_payment_methods'];
      final isPaymentsComplete = (enabledMethods is List && enabledMethods.isNotEmpty) ||
          sett == null;

      final missing = <String>[];
      int completed = 0;
      if (isProfileComplete) {
        completed++;
      } else {
        missing.add('Station details & map pin');
      }
      if (isScheduleComplete) {
        completed++;
      } else {
        missing.add('Operating schedule');
      }
      if (isDeliveryComplete) {
        completed++;
      } else {
        missing.add('Delivery rules');
      }
      if (hasActiveProduct) {
        completed++;
      } else {
        missing.add('Products & catalog');
      }
      if (isPaymentsComplete) {
        completed++;
      } else {
        missing.add('Accepted payment methods');
      }

      final isComplete = completed == 5;
      final percentage = (completed / 5 * 100).round();
      final availability = prof?['station_availability']?.toString() ??
          (isComplete ? 'closed' : 'incomplete_setup');
      final isOpen = prof?['is_open'] == true;

      return StationSetupStatus(
        isComplete: isComplete,
        completedCount: completed,
        totalSections: 5,
        percentage: percentage,
        eligibleToOpen: isComplete,
        currentAvailability: availability,
        isOpen: isOpen,
        missingFields: missing,
        profileSection: StationSectionStatus(
          isComplete: isProfileComplete,
          title: 'Station details',
          statusText: isProfileComplete ? 'Complete' : 'Missing details or map pin',
          badgeText: isProfileComplete ? 'Complete' : 'Required',
        ),
        scheduleSection: StationSectionStatus(
          isComplete: isScheduleComplete,
          title: 'Operating schedule',
          statusText: isScheduleComplete ? 'Complete' : 'Set opening hours and operating days',
          badgeText: isScheduleComplete ? 'Complete' : 'Required',
        ),
        deliverySection: StationSectionStatus(
          isComplete: isDeliveryComplete,
          title: 'Pricing & delivery rules',
          statusText: isDeliveryComplete ? 'Complete' : 'Review delivery policy',
          badgeText: isDeliveryComplete ? 'Complete' : 'Required',
        ),
        productsSection: StationSectionStatus(
          isComplete: hasActiveProduct,
          title: 'Water products & catalog',
          statusText: hasActiveProduct ? 'Complete' : 'Add at least 1 orderable product',
          badgeText: hasActiveProduct ? 'Complete' : 'Action needed',
        ),
        paymentsSection: StationSectionStatus(
          isComplete: isPaymentsComplete,
          title: 'Accepted payment methods',
          statusText: isPaymentsComplete ? 'Complete' : 'Select accepted payment methods',
          badgeText: isPaymentsComplete ? 'Complete' : 'Required',
        ),
      );
    } catch (e) {
      debugPrint('Local evaluation error: $e');
      return StationSetupStatus.empty();
    }
  }

  Future<bool> saveOperatingSchedule({
    required String ownerId,
    required String openingTime,
    required String closingTime,
    required List<String> operatingDays,
  }) async {
    try {
      await _client.from('owner_settings').upsert({
        'owner_id': ownerId,
        'opening_time': openingTime,
        'closing_time': closingTime,
        'operating_days': operatingDays,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'owner_id');
      return true;
    } catch (e) {
      debugPrint('Error saving operating schedule: $e');
      rethrow;
    }
  }

  Future<void> seedStandardProducts(String ownerId) async {
    try {
      await _client.rpc('seed_station_standard_products', params: {'p_owner_id': ownerId});
      return;
    } catch (e) {
      debugPrint('seed_station_standard_products rpc error, attempting direct insert fallback: $e');
    }

    try {
      final existing = await _client
          .from('products')
          .select('name')
          .eq('owner_id', ownerId);
      final names = (existing as List)
          .map((p) => p['name']?.toString().toLowerCase().trim())
          .toSet();

      if (!names.contains('empty 5 gallon round water container')) {
        await _client.from('products').insert({
          'owner_id': ownerId,
          'name': 'Empty 5 Gallon Round Water Container',
          'description': 'Empty reusable 5-gallon round water container for water refilling use.',
          'price': 180.00,
          'category': 'Accessories',
          'container_size': '5 gallon',
          'stock_level': 50,
          'low_stock_threshold': 10,
          'preparation_minutes': 5,
          'is_available': true,
        });
      }

      if (!names.contains('non spill cap for 5 gallon round')) {
        await _client.from('products').insert({
          'owner_id': ownerId,
          'name': 'Non spill Cap for 5 Gallon Round',
          'description': 'Non-spill cap designed for compatible 5-gallon round water containers.',
          'price': 15.00,
          'category': 'Accessories',
          'container_size': 'Cap',
          'stock_level': 100,
          'low_stock_threshold': 20,
          'preparation_minutes': 1,
          'is_available': true,
        });
      }
    } catch (fallbackErr) {
      debugPrint('Direct product seeding fallback error: $fallbackErr');
    }
  }
}

