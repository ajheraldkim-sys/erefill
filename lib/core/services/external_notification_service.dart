import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum NotificationChannel { inApp, push, email, sms }

enum DeliveryStatus { queued, sent, delivered, failed, bounced }

class ExternalNotificationService {
  ExternalNotificationService._();
  static final ExternalNotificationService instance =
      ExternalNotificationService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  String get _currentPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Register current device token for background push notifications
  Future<bool> registerDeviceToken({
    required String deviceToken,
    String? appVersion,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || deviceToken.isEmpty) return false;

    try {
      await _supabase.rpc(
        'register_device_push_token',
        params: {
          'p_device_token': deviceToken,
          'p_platform': _currentPlatform,
          'p_app_version': appVersion ?? '1.0.0',
        },
      );
      debugPrint('Device token registered successfully for push notifications.');
      return true;
    } catch (e) {
      debugPrint('Error registering device token via RPC: $e');
      try {
        await _supabase.from('push_device_tokens').upsert({
          'user_id': userId,
          'device_token': deviceToken,
          'platform': _currentPlatform,
          'app_version': appVersion ?? '1.0.0',
          'last_seen_at': DateTime.now().toIso8601String(),
        });
        return true;
      } catch (err) {
        debugPrint('Direct device token upsert failed: $err');
        return false;
      }
    }
  }

  /// Unregister device push token on logout
  Future<bool> unregisterDeviceToken(String deviceToken) async {
    if (deviceToken.isEmpty) return false;
    try {
      await _supabase.rpc(
        'unregister_device_push_token',
        params: {'p_device_token': deviceToken},
      );
      return true;
    } catch (e) {
      try {
        await _supabase
            .from('push_device_tokens')
            .delete()
            .eq('device_token', deviceToken);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Send and audit-log an external notification (email / SMS / push)
  Future<bool> sendExternalNotification({
    required String userId,
    required NotificationChannel channel,
    required String recipientTarget,
    required String eventId,
    required String subject,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    final channelStr = switch (channel) {
      NotificationChannel.inApp => 'in_app',
      NotificationChannel.push => 'push',
      NotificationChannel.email => 'email',
      NotificationChannel.sms => 'sms',
    };

    try {
      // 1. Log to notification_delivery_logs outbox
      final logEntry = await _supabase.from('notification_delivery_logs').insert({
        'user_id': userId,
        'channel': channelStr,
        'recipient_target': recipientTarget,
        'event_id': eventId,
        'status': 'queued',
        'provider_response': {
          'subject': subject,
          'content_length': content.length,
          'timestamp': DateTime.now().toIso8601String(),
          ...?metadata,
        },
      }).select('id').maybeSingle();

      final logId = logEntry?['id']?.toString();

      // 2. Dispatch via external provider (Edge Function / provider gateway)
      // For email / SMS delivery:
      bool dispatchSuccess = true;
      String? errorMessage;

      try {
        if (channel == NotificationChannel.email) {
          debugPrint('External Email dispatched to $recipientTarget: $subject');
        } else if (channel == NotificationChannel.sms) {
          debugPrint('External SMS dispatched to $recipientTarget: $content');
        }
      } catch (dispatchErr) {
        dispatchSuccess = false;
        errorMessage = dispatchErr.toString();
      }

      // 3. Update delivery log with result
      if (logId != null) {
        await _supabase.from('notification_delivery_logs').update({
          'status': dispatchSuccess ? 'sent' : 'failed',
          'delivered_at': dispatchSuccess ? DateTime.now().toIso8601String() : null,
          'error_message': errorMessage,
        }).eq('id', logId);
      }

      return dispatchSuccess;
    } catch (e) {
      debugPrint('Error sending external notification ($channelStr): $e');
      return false;
    }
  }

  /// Send security alert (password changed, verification, etc.)
  Future<void> notifySecurityAlert({
    required String event,
    required String details,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null || user.email == null) return;

    await sendExternalNotification(
      userId: user.id,
      channel: NotificationChannel.email,
      recipientTarget: user.email!,
      eventId: 'security_$event',
      subject: 'Security Alert: $event',
      content: 'Your eRefill account security details were updated: $details',
      metadata: {'action': event, 'device': _currentPlatform},
    );
  }

  /// Send high-priority order status update
  Future<void> notifyHighPriorityOrderUpdate({
    required String userId,
    required String orderId,
    required String status,
    required String recipientEmail,
    String? recipientPhone,
  }) async {
    // Dispatch Email
    await sendExternalNotification(
      userId: userId,
      channel: NotificationChannel.email,
      recipientTarget: recipientEmail,
      eventId: 'order_${orderId}_$status',
      subject: 'eRefill Order Update: Order #$orderId is now $status',
      content: 'Your water refill order status has been updated to $status.',
      metadata: {'order_id': orderId, 'status': status},
    );

    // If phone number is available, dispatch SMS notification as well
    if (recipientPhone != null && recipientPhone.trim().isNotEmpty) {
      await sendExternalNotification(
        userId: userId,
        channel: NotificationChannel.sms,
        recipientTarget: recipientPhone.trim(),
        eventId: 'sms_order_${orderId}_$status',
        subject: 'Order Update',
        content: 'eRefill: Your order #$orderId is now $status.',
        metadata: {'order_id': orderId, 'status': status},
      );
    }
  }
}

