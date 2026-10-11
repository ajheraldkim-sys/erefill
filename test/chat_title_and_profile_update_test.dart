import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/utils/supabase_helpers.dart';
import 'package:erefill/features/chat/models/chat_room.dart';

void main() {
  group('SupabaseHelpers.isMissingColumnError tests', () {
    test('correctly identifies single-quoted missing column from PGRST204', () {
      final error = Exception(
        "Could not find the 'updated_at' column of 'profiles' in the schema cache, code: PGRST204",
      );
      expect(
        SupabaseHelpers.isMissingColumnError(error, 'updated_at'),
        isTrue,
      );
    });

    test('correctly identifies double-quoted and prefixed missing column', () {
      final error = Exception(
        'column "purok" of relation "profiles" does not exist (42703)',
      );
      expect(
        SupabaseHelpers.isMissingColumnError(error, 'purok'),
        isTrue,
      );
    });

    test('returns false for unrelated errors', () {
      final error = Exception('Network timeout connection refused');
      expect(
        SupabaseHelpers.isMissingColumnError(error, 'updated_at'),
        isFalse,
      );
    });
  });

  group('ChatRoom title and participant display tests', () {
    test('isGenericTitle flags generic placeholders', () {
      expect(ChatRoom.isGenericTitle('Order Delivery'), isTrue);
      expect(ChatRoom.isGenericTitle('order_delivery'), isTrue);
      expect(ChatRoom.isGenericTitle('order'), isTrue);
      expect(ChatRoom.isGenericTitle('delivery'), isTrue);
      expect(ChatRoom.isGenericTitle('Chat'), isTrue);
      expect(ChatRoom.isGenericTitle('Support Chat'), isTrue);
      expect(ChatRoom.isGenericTitle(null), isTrue);
      expect(ChatRoom.isGenericTitle(''), isTrue);

      expect(ChatRoom.isGenericTitle('Juan Dela Cruz'), isFalse);
      expect(ChatRoom.isGenericTitle('AquaPure Refill Station'), isFalse);
      expect(ChatRoom.isGenericTitle('Carlos Mendoza'), isFalse);
    });

    test('displayTitle resolves actual user name for owner instead of Order Delivery', () {
      final room = ChatRoom(
        id: 'room-1',
        roomType: ChatRoomType.orderDelivery,
        referenceId: 'ord-12345678',
        status: ChatRoomStatus.active,
        ownerId: 'owner-1',
        title: 'Order Delivery', // Generic title stored in DB
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        participants: [
          ChatParticipant(
            id: 'p-1',
            roomId: 'room-1',
            userId: 'owner-1',
            roleInRoom: ParticipantRole.owner,
            joinedAt: DateTime.now(),
            userProfile: {'full_name': 'AquaPure Station'},
          ),
          ChatParticipant(
            id: 'p-2',
            roomId: 'room-1',
            userId: 'cust-1',
            roleInRoom: ParticipantRole.customer,
            joinedAt: DateTime.now(),
            userProfile: {'full_name': 'Maria Santos'},
          ),
        ],
      );

      // When the owner views the chat room, they should see customer's name ("Maria Santos")
      expect(
        room.getDisplayTitle(currentUserId: 'owner-1'),
        equals('Maria Santos'),
      );
    });

    test('displayTitle resolves rider name for customer when rider is assigned', () {
      final room = ChatRoom(
        id: 'room-2',
        roomType: ChatRoomType.orderDelivery,
        referenceId: 'ord-abcdef12',
        status: ChatRoomStatus.active,
        ownerId: 'owner-1',
        title: 'Order Delivery',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        participants: [
          ChatParticipant(
            id: 'p-1',
            roomId: 'room-2',
            userId: 'owner-1',
            roleInRoom: ParticipantRole.owner,
            joinedAt: DateTime.now(),
            userProfile: {'full_name': 'AquaPure Station'},
          ),
          ChatParticipant(
            id: 'p-2',
            roomId: 'room-2',
            userId: 'cust-1',
            roleInRoom: ParticipantRole.customer,
            joinedAt: DateTime.now(),
            userProfile: {'full_name': 'Maria Santos'},
          ),
          ChatParticipant(
            id: 'p-3',
            roomId: 'room-2',
            userId: 'rider-1',
            roleInRoom: ParticipantRole.rider,
            joinedAt: DateTime.now(),
            userProfile: {'full_name': 'Carlos Cruz'},
          ),
        ],
      );

      // When the customer views the chat room with assigned rider, they see the rider's name
      expect(
        room.getDisplayTitle(currentUserId: 'cust-1'),
        equals('Carlos Cruz (Rider)'),
      );
    });

    test('displayTitle falls back to metadata when participant profiles not loaded', () {
      final room = ChatRoom(
        id: 'room-3',
        roomType: ChatRoomType.orderDelivery,
        referenceId: 'ord-99887766',
        status: ChatRoomStatus.active,
        ownerId: 'owner-1',
        title: 'Order Delivery',
        metadata: {
          'customer_name': 'Juan Dela Cruz',
          'station_name': 'Crystal Clear Waters',
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        participants: null,
      );

      // Should return customer_name from metadata instead of "Order Delivery"
      expect(
        room.getDisplayTitle(),
        equals('Juan Dela Cruz'),
      );
    });

    test('displayTitle falls back to order ID instead of Order Delivery when no name available', () {
      final room = ChatRoom(
        id: 'room-4',
        roomType: ChatRoomType.orderDelivery,
        referenceId: 'c74a108b-98f2',
        status: ChatRoomStatus.active,
        ownerId: 'owner-1',
        title: 'Order Delivery',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        participants: null,
      );

      expect(
        room.getDisplayTitle(),
        equals('Order #C74A108B'),
      );
    });
  });
}

