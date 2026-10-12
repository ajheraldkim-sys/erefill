import '../models/chat_room.dart';

/// Centralized utility for role-based chat identity resolution in Erefill.
///
/// Ensures correct display names from recipient's perspective across all channels:
/// - Rider ↔ Customer: Rider name for Customer, Customer name for Rider.
/// - Customer ↔ Owner: Station name for Customer, Customer name for Owner.
/// - Owner ↔ Rider: Station name for Rider, Rider name for Owner.
class ChatIdentityResolver {
  ChatIdentityResolver._();

  /// Resolve the display name of a message sender from the current user's perspective.
  ///
  /// Returns:
  /// - "You" if [isMine] is true or [senderId] matches [currentUserId].
  /// - "System" if message is a system message.
  /// - The station name if sender is an Owner and viewer is a Customer or Rider.
  /// - The customer's full name if sender is a Customer.
  /// - The rider's full name if sender is a Rider.
  static String resolveSenderName({
    required String? senderId,
    required String? currentUserId,
    required String? currentUserRole,
    ParticipantRole? senderRole,
    Map<String, dynamic>? senderProfile,
    Map<String, dynamic>? roomMetadata,
    Map<String, dynamic>? orderContext,
    ChatRoomType? roomType,
    bool isSystemMessage = false,
  }) {
    if (isSystemMessage || senderId == null || senderId.isEmpty) {
      return 'System';
    }

    if (currentUserId != null && senderId == currentUserId) {
      return 'You';
    }

    final viewerRole = (currentUserRole ?? '').trim().toLowerCase();

    // 1. Determine sender role: from explicit senderRole, senderProfile, or metadata
    ParticipantRole resolvedRole = senderRole ?? ParticipantRole.customer;
    final profileRole = senderProfile?['role']?.toString().toLowerCase();
    if (profileRole != null && profileRole.isNotEmpty) {
      resolvedRole = ParticipantRole.fromString(profileRole);
    }

    // 2. Extract profile fields
    final profileFullName = senderProfile?['full_name']?.toString().trim();
    final profileStationName = senderProfile?['station_name']?.toString().trim();
    final profileUsername = senderProfile?['username']?.toString().trim();

    // 3. Extract metadata / orderContext fallbacks
    final metaStationName = roomMetadata?['station_name']?.toString().trim() ??
        orderContext?['station_name']?.toString().trim();
    final metaCustomerName = roomMetadata?['customer_name']?.toString().trim() ??
        orderContext?['customer_name']?.toString().trim();
    final metaRiderName = roomMetadata?['rider_name']?.toString().trim();

    // 4. Role Matrix Resolution
    switch (resolvedRole) {
      case ParticipantRole.owner:
        // When Owner sends a message to Customer or Rider, display Station Name
        if (viewerRole == 'customer' || viewerRole == 'rider' || roomType == ChatRoomType.customerSupport || roomType == ChatRoomType.riderDispatch) {
          if (metaStationName != null && metaStationName.isNotEmpty && !ChatRoom.isGenericTitle(metaStationName)) {
            return metaStationName;
          }
          if (profileStationName != null && profileStationName.isNotEmpty && !ChatRoom.isGenericTitle(profileStationName)) {
            return profileStationName;
          }
          if (profileFullName != null && profileFullName.isNotEmpty && !ChatRoom.isGenericTitle(profileFullName)) {
            return '$profileFullName (Station)';
          }
          return 'Refill Station';
        }
        return _pickValidName([profileFullName, profileUsername, 'Station Owner']);

      case ParticipantRole.rider:
        // Rider sends message: Customer or Owner sees Rider's name
        if (metaRiderName != null && metaRiderName.isNotEmpty && !ChatRoom.isGenericTitle(metaRiderName)) {
          return metaRiderName;
        }
        if (profileFullName != null && profileFullName.isNotEmpty && !ChatRoom.isGenericTitle(profileFullName)) {
          return profileFullName;
        }
        if (profileUsername != null && profileUsername.isNotEmpty) {
          return profileUsername;
        }
        return 'Delivery Rider';

      case ParticipantRole.customer:
        // Customer sends message: Rider or Owner sees Customer's name
        if (metaCustomerName != null && metaCustomerName.isNotEmpty && !ChatRoom.isGenericTitle(metaCustomerName)) {
          return metaCustomerName;
        }
        if (profileFullName != null && profileFullName.isNotEmpty && !ChatRoom.isGenericTitle(profileFullName)) {
          return profileFullName;
        }
        if (profileUsername != null && profileUsername.isNotEmpty) {
          return profileUsername;
        }
        return 'Customer';

      case ParticipantRole.system:
        return 'System';
    }
  }

  /// Resolve conversation title from current viewer's perspective.
  ///
  /// Examples:
  /// - Customer viewing Rider chat -> "Juan Dela Cruz (Rider)"
  /// - Rider viewing Customer chat -> "Maria Santos"
  /// - Customer viewing Station chat -> "AquaPure Station"
  /// - Owner viewing Customer chat -> "Maria Santos"
  /// - Owner viewing Rider chat -> "Juan Dela Cruz (Rider)"
  /// - Rider viewing Station chat -> "AquaPure Station"
  static String resolveRoomDisplayTitle({
    required ChatRoom room,
    required String? currentUserId,
    required String? currentUserRole,
    Map<String, dynamic>? orderContext,
  }) {
    final viewerRole = (currentUserRole ?? '').trim().toLowerCase();
    final metadata = room.metadata;
    final channel = metadata['channel']?.toString().toLowerCase();

    final metaStation = metadata['station_name']?.toString().trim() ??
        orderContext?['station_name']?.toString().trim();
    final metaCustomer = metadata['customer_name']?.toString().trim() ??
        orderContext?['customer_name']?.toString().trim();
    final metaRider = metadata['rider_name']?.toString().trim();

    // 1. Channel-specific explicit matching
    if (channel == 'customer_rider' || room.roomType == ChatRoomType.orderDelivery) {
      if (viewerRole == 'customer') {
        // Customer sees rider
        if (metaRider != null && metaRider.isNotEmpty && !ChatRoom.isGenericTitle(metaRider)) {
          return '$metaRider (Rider)';
        }
        final riderPart = _findParticipantByRole(room.participants, ParticipantRole.rider);
        if (riderPart != null) {
          final name = _getParticipantName(riderPart);
          if (name != null) return '$name (Rider)';
        }
        return 'Delivery Rider';
      } else if (viewerRole == 'rider') {
        // Rider sees customer
        if (metaCustomer != null && metaCustomer.isNotEmpty && !ChatRoom.isGenericTitle(metaCustomer)) {
          return metaCustomer;
        }
        final custPart = _findParticipantByRole(room.participants, ParticipantRole.customer);
        if (custPart != null) {
          final name = _getParticipantName(custPart);
          if (name != null) return name;
        }
        return 'Customer';
      }
    }

    if (channel == 'customer_owner' || room.roomType == ChatRoomType.customerSupport) {
      if (viewerRole == 'customer') {
        // Customer sees station
        if (metaStation != null && metaStation.isNotEmpty && !ChatRoom.isGenericTitle(metaStation)) {
          return metaStation;
        }
        final ownerPart = _findParticipantByRole(room.participants, ParticipantRole.owner);
        if (ownerPart != null) {
          final station = ownerPart.userProfile?['station_name']?.toString().trim();
          if (station != null && station.isNotEmpty && !ChatRoom.isGenericTitle(station)) {
            return station;
          }
          final name = _getParticipantName(ownerPart);
          if (name != null) return name;
        }
        return 'Refill Station Support';
      } else if (viewerRole == 'owner') {
        // Owner sees customer
        if (metaCustomer != null && metaCustomer.isNotEmpty && !ChatRoom.isGenericTitle(metaCustomer)) {
          return metaCustomer;
        }
        final custPart = _findParticipantByRole(room.participants, ParticipantRole.customer);
        if (custPart != null) {
          final name = _getParticipantName(custPart);
          if (name != null) return name;
        }
        return 'Customer';
      }
    }

    if (channel == 'owner_rider' || room.roomType == ChatRoomType.riderDispatch) {
      if (viewerRole == 'rider') {
        // Rider sees station
        if (metaStation != null && metaStation.isNotEmpty && !ChatRoom.isGenericTitle(metaStation)) {
          return metaStation;
        }
        final ownerPart = _findParticipantByRole(room.participants, ParticipantRole.owner);
        if (ownerPart != null) {
          final station = ownerPart.userProfile?['station_name']?.toString().trim();
          if (station != null && station.isNotEmpty && !ChatRoom.isGenericTitle(station)) {
            return station;
          }
          final name = _getParticipantName(ownerPart);
          if (name != null) return name;
        }
        return 'Refill Station';
      } else if (viewerRole == 'owner') {
        // Owner sees rider
        if (metaRider != null && metaRider.isNotEmpty && !ChatRoom.isGenericTitle(metaRider)) {
          return '$metaRider (Rider)';
        }
        final riderPart = _findParticipantByRole(room.participants, ParticipantRole.rider);
        if (riderPart != null) {
          final name = _getParticipantName(riderPart);
          if (name != null) return '$name (Rider)';
        }
        return 'Delivery Rider';
      }
    }

    // 2. Fall back to standard room.getDisplayTitle
    return room.getDisplayTitle(currentUserId: currentUserId);
  }

  /// Resolve descriptive subtitle for a chat room header.
  static String resolveRoomSubtitle({
    required ChatRoom? room,
    required String? currentUserRole,
    Map<String, dynamic>? orderContext,
  }) {
    final stationName = room?.metadata['station_name']?.toString() ??
        orderContext?['station_name']?.toString();
    final orderStatus = orderContext?['status']?.toString();

    if (stationName != null && stationName.isNotEmpty) {
      if (orderStatus != null && orderStatus.isNotEmpty) {
        final formatted = orderStatus.replaceAll('_', ' ');
        return '$stationName • ${formatted[0].toUpperCase()}${formatted.substring(1)}';
      }
      return stationName;
    }

    if (room != null) {
      switch (room.roomType) {
        case ChatRoomType.orderDelivery:
          return 'Delivery coordination';
        case ChatRoomType.customerSupport:
          return 'Station support channel';
        case ChatRoomType.riderDispatch:
          return 'Station dispatch channel';
        case ChatRoomType.broadcast:
          return 'Announcement channel';
      }
    }

    return 'Refill conversation';
  }

  static ChatParticipant? _findParticipantByRole(
    List<ChatParticipant>? participants,
    ParticipantRole role,
  ) {
    if (participants == null || participants.isEmpty) return null;
    try {
      return participants.firstWhere((p) => p.roleInRoom == role);
    } catch (_) {
      return null;
    }
  }

  static String? _getParticipantName(ChatParticipant p) {
    final profile = p.userProfile;
    if (profile == null) return null;
    final full = profile['full_name']?.toString().trim();
    if (full != null && full.isNotEmpty && !ChatRoom.isGenericTitle(full)) {
      return full;
    }
    final user = profile['username']?.toString().trim();
    if (user != null && user.isNotEmpty && !ChatRoom.isGenericTitle(user)) {
      return user;
    }
    return null;
  }

  static String _pickValidName(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty && !ChatRoom.isGenericTitle(c)) {
        return c.trim();
      }
    }
    return 'User';
  }
}

