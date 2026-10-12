import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/chat/models/chat_room.dart';
import 'package:erefill/features/chat/utils/chat_identity_resolver.dart';

void main() {
  group('ChatIdentityResolver Role-Based Sender Name Matrix Tests', () {
    const customerId = 'cust-101';
    const riderId = 'rider-202';
    const ownerId = 'owner-303';

    final customerProfile = {
      'id': customerId,
      'full_name': 'Maria Santos',
      'role': 'customer',
    };

    final riderProfile = {
      'id': riderId,
      'full_name': 'Juan Dela Cruz',
      'role': 'rider',
    };

    final ownerProfile = {
      'id': ownerId,
      'full_name': 'Carlos Mendoza',
      'station_name': 'AquaPure Refill Hub',
      'role': 'owner',
    };

    final roomMeta = {
      'station_name': 'AquaPure Refill Hub',
      'customer_name': 'Maria Santos',
      'rider_name': 'Juan Dela Cruz',
    };

    test('1. Rider -> Customer: Customer sees Rider full name', () {
      final name = ChatIdentityResolver.resolveSenderName(
        senderId: riderId,
        currentUserId: customerId,
        currentUserRole: 'customer',
        senderRole: ParticipantRole.rider,
        senderProfile: riderProfile,
        roomMetadata: roomMeta,
        roomType: ChatRoomType.orderDelivery,
      );
      expect(name, equals('Juan Dela Cruz'));
    });

    test('2. Customer -> Rider: Rider sees Customer full name', () {
      final name = ChatIdentityResolver.resolveSenderName(
        senderId: customerId,
        currentUserId: riderId,
        currentUserRole: 'rider',
        senderRole: ParticipantRole.customer,
        senderProfile: customerProfile,
        roomMetadata: roomMeta,
        roomType: ChatRoomType.orderDelivery,
      );
      expect(name, equals('Maria Santos'));
    });

    test('3. Customer -> Owner: Owner sees Customer full name', () {
      final name = ChatIdentityResolver.resolveSenderName(
        senderId: customerId,
        currentUserId: ownerId,
        currentUserRole: 'owner',
        senderRole: ParticipantRole.customer,
        senderProfile: customerProfile,
        roomMetadata: roomMeta,
        roomType: ChatRoomType.customerSupport,
      );
      expect(name, equals('Maria Santos'));
    });

    test('4. Owner -> Customer: Customer sees Station Name', () {
      final name = ChatIdentityResolver.resolveSenderName(
        senderId: ownerId,
        currentUserId: customerId,
        currentUserRole: 'customer',
        senderRole: ParticipantRole.owner,
        senderProfile: ownerProfile,
        roomMetadata: roomMeta,
        roomType: ChatRoomType.customerSupport,
      );
      expect(name, equals('AquaPure Refill Hub'));
    });

    test('5. Rider -> Owner: Owner sees Rider full name', () {
      final name = ChatIdentityResolver.resolveSenderName(
        senderId: riderId,
        currentUserId: ownerId,
        currentUserRole: 'owner',
        senderRole: ParticipantRole.rider,
        senderProfile: riderProfile,
        roomMetadata: roomMeta,
        roomType: ChatRoomType.riderDispatch,
      );
      expect(name, equals('Juan Dela Cruz'));
    });

    test('6. Owner -> Rider: Rider sees Station Name', () {
      final name = ChatIdentityResolver.resolveSenderName(
        senderId: ownerId,
        currentUserId: riderId,
        currentUserRole: 'rider',
        senderRole: ParticipantRole.owner,
        senderProfile: ownerProfile,
        roomMetadata: roomMeta,
        roomType: ChatRoomType.riderDispatch,
      );
      expect(name, equals('AquaPure Refill Hub'));
    });

    test('7. Sender own messages always resolve to You', () {
      expect(
        ChatIdentityResolver.resolveSenderName(
          senderId: customerId,
          currentUserId: customerId,
          currentUserRole: 'customer',
          senderProfile: customerProfile,
        ),
        equals('You'),
      );
      expect(
        ChatIdentityResolver.resolveSenderName(
          senderId: riderId,
          currentUserId: riderId,
          currentUserRole: 'rider',
          senderProfile: riderProfile,
        ),
        equals('You'),
      );
      expect(
        ChatIdentityResolver.resolveSenderName(
          senderId: ownerId,
          currentUserId: ownerId,
          currentUserRole: 'owner',
          senderProfile: ownerProfile,
        ),
        equals('You'),
      );
    });

    test('8. System messages resolve to System', () {
      expect(
        ChatIdentityResolver.resolveSenderName(
          senderId: null,
          currentUserId: customerId,
          currentUserRole: 'customer',
          isSystemMessage: true,
        ),
        equals('System'),
      );
    });
  });

  group('ChatIdentityResolver Room Display Title Tests', () {
    test('Customer viewing Customer-Rider chat sees Rider name with tag', () {
      final room = ChatRoom(
        id: 'room-cr',
        roomType: ChatRoomType.orderDelivery,
        status: ChatRoomStatus.active,
        title: 'Order Delivery',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: {
          'channel': 'customer_rider',
          'rider_name': 'Juan Dela Cruz',
          'customer_name': 'Maria Santos',
        },
      );

      final title = ChatIdentityResolver.resolveRoomDisplayTitle(
        room: room,
        currentUserId: 'cust-101',
        currentUserRole: 'customer',
      );
      expect(title, equals('Juan Dela Cruz (Rider)'));
    });

    test('Rider viewing Customer-Rider chat sees Customer name', () {
      final room = ChatRoom(
        id: 'room-cr',
        roomType: ChatRoomType.orderDelivery,
        status: ChatRoomStatus.active,
        title: 'Order Delivery',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: {
          'channel': 'customer_rider',
          'rider_name': 'Juan Dela Cruz',
          'customer_name': 'Maria Santos',
        },
      );

      final title = ChatIdentityResolver.resolveRoomDisplayTitle(
        room: room,
        currentUserId: 'rider-202',
        currentUserRole: 'rider',
      );
      expect(title, equals('Maria Santos'));
    });

    test('Customer viewing Station Support sees Station Name', () {
      final room = ChatRoom(
        id: 'room-cs',
        roomType: ChatRoomType.customerSupport,
        status: ChatRoomStatus.active,
        title: 'Support Chat',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: {
          'channel': 'customer_owner',
          'station_name': 'AquaPure Refill Hub',
          'customer_name': 'Maria Santos',
        },
      );

      final title = ChatIdentityResolver.resolveRoomDisplayTitle(
        room: room,
        currentUserId: 'cust-101',
        currentUserRole: 'customer',
      );
      expect(title, equals('AquaPure Refill Hub'));
    });

    test('Owner viewing Station Support sees Customer name', () {
      final room = ChatRoom(
        id: 'room-cs',
        roomType: ChatRoomType.customerSupport,
        status: ChatRoomStatus.active,
        title: 'Support Chat',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: {
          'channel': 'customer_owner',
          'station_name': 'AquaPure Refill Hub',
          'customer_name': 'Maria Santos',
        },
      );

      final title = ChatIdentityResolver.resolveRoomDisplayTitle(
        room: room,
        currentUserId: 'owner-303',
        currentUserRole: 'owner',
      );
      expect(title, equals('Maria Santos'));
    });

    test('Rider viewing Dispatch channel sees Station Name', () {
      final room = ChatRoom(
        id: 'room-rd',
        roomType: ChatRoomType.riderDispatch,
        status: ChatRoomStatus.active,
        title: 'Dispatch Channel',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: {
          'channel': 'owner_rider',
          'station_name': 'AquaPure Refill Hub',
          'rider_name': 'Juan Dela Cruz',
        },
      );

      final title = ChatIdentityResolver.resolveRoomDisplayTitle(
        room: room,
        currentUserId: 'rider-202',
        currentUserRole: 'rider',
      );
      expect(title, equals('AquaPure Refill Hub'));
    });

    test('Owner viewing Dispatch channel sees Rider Name', () {
      final room = ChatRoom(
        id: 'room-rd',
        roomType: ChatRoomType.riderDispatch,
        status: ChatRoomStatus.active,
        title: 'Dispatch Channel',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: {
          'channel': 'owner_rider',
          'station_name': 'AquaPure Refill Hub',
          'rider_name': 'Juan Dela Cruz',
        },
      );

      final title = ChatIdentityResolver.resolveRoomDisplayTitle(
        room: room,
        currentUserId: 'owner-303',
        currentUserRole: 'owner',
      );
      expect(title, equals('Juan Dela Cruz (Rider)'));
    });
  });
}

