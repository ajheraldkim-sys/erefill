import 'package:erefill/core/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserModel Profile and Role Attributes Tests', () {
    test('UserModel.fromJson properly parses role-specific profile fields', () {
      final json = {
        'id': 'user-123',
        'email': 'owner@erefill.com',
        'first_name': 'Juan',
        'last_name': 'Dela Cruz',
        'mi': 'P',
        'suffix': 'Jr.',
        'phone': '09123456789',
        'role': 'owner',
        'station_name': 'AquaFlow Purified Water',
        'vehicle_type': 'Motorcycle with Carrier',
        'license_number': 'N01-12-345678',
        'town': 'Cantilan',
        'barangay': 'Lininti-an',
        'updated_at': '2026-10-08T05:00:00Z',
      };

      final user = UserModel.fromJson(json);

      expect(user.id, 'user-123');
      expect(user.email, 'owner@erefill.com');
      expect(user.firstName, 'Juan');
      expect(user.lastName, 'Dela Cruz');
      expect(user.mi, 'P');
      expect(user.suffix, 'Jr.');
      expect(user.phone, '09123456789');
      expect(user.role, 'owner');
      expect(user.stationName, 'AquaFlow Purified Water');
      expect(user.vehicleType, 'Motorcycle with Carrier');
      expect(user.licenseNumber, 'N01-12-345678');
      expect(user.town, 'Cantilan');
      expect(user.barangay, 'Lininti-an');
    });

    test('UserModel.copyWith preserves and updates role attributes', () {
      final initial = UserModel(
        id: 'rider-456',
        email: 'rider@erefill.com',
        role: 'rider',
        firstName: 'Pedro',
        lastName: 'Penduko',
        stationName: null,
        vehicleType: 'Tricycle',
        licenseNumber: 'A01-99-888888',
        updatedAt: DateTime.now(),
      );

      final updated = initial.copyWith(
        vehicleType: 'Motorcycle Sidecar',
        stationName: 'Cantilan Central Station',
        phone: '09987654321',
      );

      expect(updated.id, 'rider-456');
      expect(updated.role, 'rider');
      expect(updated.firstName, 'Pedro');
      expect(updated.lastName, 'Penduko');
      expect(updated.vehicleType, 'Motorcycle Sidecar');
      expect(updated.stationName, 'Cantilan Central Station');
      expect(updated.licenseNumber, 'A01-99-888888');
      expect(updated.phone, '09987654321');
    });
  });
}

