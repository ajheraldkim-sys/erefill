import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum LogLevel { info, warn, error, critical }

class ObservabilityService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Logs a structured domain event for observability and metrics
  Future<void> logEvent({
    required String type,
    required LogLevel level,
    Map<String, dynamic>? payload,
    String? orderId,
    String? riderId,
  }) async {
    final userId = _client.auth.currentUser?.id;

    // 1. Local debug print
    debugPrint('[OBSERVE] ${level.name.toUpperCase()}: $type | $payload');

    // 2. Remote persistent log (Domain Event)
    try {
      await _client.from('domain_events').insert({
        'event_type': type,
        'actor_id': userId,
        'payload': payload ?? {},
        'metadata': {
          'level': level.name,
          'order_id': orderId,
          'rider_id': riderId,
          'platform': defaultTargetPlatform.name,
          'is_web': kIsWeb,
        },
      });
    } catch (e) {
      debugPrint(
        '[OBSERVE] CRITICAL FAILURE: Could not log event to server ($e)',
      );
    }
  }

  /// Specialized log for API/Network failures
  Future<void> logFailure(
    String action,
    dynamic error, {
    String? orderId,
  }) async {
    await logEvent(
      type: 'API_FAILURE',
      level: LogLevel.error,
      orderId: orderId,
      payload: {'action': action, 'error': error.toString()},
    );
  }

  /// Records an operational metric snapshot (Step 2: Metrics)
  Future<void> recordMetric(
    String name,
    double value, {
    String? stationId,
  }) async {
    try {
      await _client.from('operational_metrics').insert({
        'station_id': stationId,
        'metric_name': name,
        'metric_value': value,
      });
    } catch (e) {
      debugPrint('[METRIC] Failed to record $name: $e');
    }
  }
}
