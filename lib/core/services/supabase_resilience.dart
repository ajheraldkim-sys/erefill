import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseResilience {
  static const int maxRetries = 3;
  static const Duration initialDelay = Duration(seconds: 1);

  /// Executes a Supabase call with exponential backoff and localized error handling
  static Future<T> execute<T>(
    Future<T> Function() call, {
    String? customErrorMessage,
    BuildContext? context,
  }) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        return await call();
      } on PostgrestException catch (e) {
        debugPrint(
          'SupabaseResilience: DB Exception - ${e.message} (Code: ${e.code})',
        );

        // Handle specific DB errors that shouldn't be retried
        if (e.code == '23505') {
          // Unique violation (e.g. idempotency key)
          // The helper validates context.mounted before showing UI.
          // ignore: use_build_context_synchronously
          _showError(context, 'This order has already been processed.');
          rethrow;
        }

        attempts++;
        if (attempts >= maxRetries) {
          // The helper validates context.mounted before showing UI.
          // ignore: use_build_context_synchronously
          _showError(
            // ignore: use_build_context_synchronously
            context,
            customErrorMessage ??
                'Service is currently unavailable. Please check your connection.',
          );
          rethrow;
        }
        await Future.delayed(initialDelay * attempts);
      } catch (e) {
        debugPrint('SupabaseResilience: General Exception - $e');
        attempts++;
        if (attempts >= maxRetries) {
          // The helper validates context.mounted before showing UI.
          // ignore: use_build_context_synchronously
          _showError(
            // ignore: use_build_context_synchronously
            context,
            'An unexpected error occurred. Please try again later.',
          );
          rethrow;
        }
        await Future.delayed(initialDelay * attempts);
      }
    }
    throw Exception('SupabaseResilience: Exhausted retries without result');
  }

  static void _showError(BuildContext? context, String message) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}
