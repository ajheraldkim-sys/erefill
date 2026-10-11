import 'package:supabase_flutter/supabase_flutter.dart';

enum ChatRoomType {
  orderDelivery,
  customerSupport,
  riderDispatch,
  broadcast;

  String get value {
    switch (this) {
      case ChatRoomType.orderDelivery:
        return 'order_delivery';
      case ChatRoomType.customerSupport:
        return 'customer_support';
      case ChatRoomType.riderDispatch:
        return 'rider_dispatch';
      case ChatRoomType.broadcast:
        return 'broadcast';
    }
  }

  static ChatRoomType fromString(String value) {
    switch (value) {
      case 'order_delivery':
        return ChatRoomType.orderDelivery;
      case 'customer_support':
        return ChatRoomType.customerSupport;
      case 'rider_dispatch':
        return ChatRoomType.riderDispatch;
      case 'broadcast':
        return ChatRoomType.broadcast;
      default:
        return ChatRoomType.customerSupport;
    }
  }
}

enum ChatRoomStatus {
  active,
  archived,
  closed;

  String get value {
    switch (this) {
      case ChatRoomStatus.active:
        return 'active';
      case ChatRoomStatus.archived:
        return 'archived';
      case ChatRoomStatus.closed:
        return 'closed';
    }
  }

  static ChatRoomStatus fromString(String value) {
    switch (value) {
      case 'active':
        return ChatRoomStatus.active;
      case 'archived':
        return ChatRoomStatus.archived;
      case 'closed':
        return ChatRoomStatus.closed;
      default:
        return ChatRoomStatus.active;
    }
  }
}

class ChatRoom {
  final String id;
  final ChatRoomType roomType;
  final String? referenceId; // order_id for order_delivery rooms
  final ChatRoomStatus status;
  final String? ownerId;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final Map<String, dynamic> metadata;

  // Joined fields from participants/messages
  final List<ChatParticipant>? participants;
  final Message? lastMessage;
  final int? unreadCount;

  ChatRoom({
    required this.id,
    required this.roomType,
    this.referenceId,
    required this.status,
    this.ownerId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
    this.metadata = const {},
    this.participants,
    this.lastMessage,
    this.unreadCount,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    // Safely extract string values with null checks
    final id = json['id']?.toString() ?? 'temp-room-id';

    final roomTypeStr = json['room_type']?.toString() ?? 'order_delivery';
    final statusStr = json['status']?.toString() ?? 'active';
    final createdAtStr = json['created_at']?.toString();
    final updatedAtStr = json['updated_at']?.toString();

    return ChatRoom(
      id: id,
      roomType: ChatRoomType.fromString(roomTypeStr),
      referenceId: json['reference_id']?.toString(),
      status: ChatRoomStatus.fromString(statusStr),
      ownerId: json['owner_id']?.toString(),
      title: json['title']?.toString(),
      createdAt: DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAtStr ?? '') ?? DateTime.now(),
      archivedAt: json['archived_at'] != null
          ? DateTime.tryParse(json['archived_at'].toString())
          : null,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      participants: (json['participants'] as List<dynamic>?)
          ?.map((e) => ChatParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastMessage: json['last_message'] != null
          ? Message.fromJson(json['last_message'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unread_count'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_type': roomType.value,
      'reference_id': referenceId,
      'status': status.value,
      'owner_id': ownerId,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'archived_at': archivedAt?.toIso8601String(),
      'metadata': metadata,
      'last_message': lastMessage?.toJson(),
      'unread_count': unreadCount,
      'participants': participants?.map((p) => p.toJson()).toList(),
    };
  }

  bool get isActive => status == ChatRoomStatus.active;
  bool get isArchived => status == ChatRoomStatus.archived;
  bool get isOrderDelivery => roomType == ChatRoomType.orderDelivery;
  bool get isCustomerSupport => roomType == ChatRoomType.customerSupport;
  bool get isRiderDispatch => roomType == ChatRoomType.riderDispatch;
  bool get isBroadcast => roomType == ChatRoomType.broadcast;

  static bool isGenericTitle(String? t) {
    if (t == null) return true;
    final lower = t.trim().toLowerCase();
    return lower.isEmpty ||
        lower == 'order delivery' ||
        lower == 'order_delivery' ||
        lower == 'order' ||
        lower == 'delivery' ||
        lower == 'chat' ||
        lower == 'support chat' ||
        lower == 'order delivery chat';
  }

  String getDisplayTitle({String? currentUserId}) {
    String? myId = currentUserId;
    if (myId == null) {
      try {
        myId = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {}
    }

    // 1. Try to find the OTHER participant (not myself) with a valid name
    if (participants != null && participants!.isNotEmpty) {
      final others = myId != null
          ? participants!.where((p) => p.userId != myId).toList()
          : participants!;

      if (others.isNotEmpty) {
        // Priority order for counterparty:
        // - If order delivery: check Rider, Customer, Owner
        final riders =
            others.where((p) => p.roleInRoom == ParticipantRole.rider).toList();
        final customers = others
            .where((p) => p.roleInRoom == ParticipantRole.customer)
            .toList();
        final owners =
            others.where((p) => p.roleInRoom == ParticipantRole.owner).toList();

        final candidates = [
          ...riders,
          ...customers,
          ...owners,
          ...others,
        ];

        for (final p in candidates) {
          final profile = p.userProfile;
          if (profile != null) {
            final fullName = profile['full_name']?.toString().trim();
            if (fullName != null &&
                fullName.isNotEmpty &&
                !isGenericTitle(fullName)) {
              if (p.roleInRoom == ParticipantRole.rider) {
                return '$fullName (Rider)';
              }
              return fullName;
            }
            final stationName = profile['station_name']?.toString().trim();
            if (stationName != null &&
                stationName.isNotEmpty &&
                !isGenericTitle(stationName)) {
              return stationName;
            }
            final username = profile['username']?.toString().trim();
            if (username != null &&
                username.isNotEmpty &&
                !isGenericTitle(username)) {
              return username;
            }
          }
        }
      }
    }

    // 2. Check metadata for explicitly stored names
    if (metadata.isNotEmpty) {
      final otherName = metadata['other_user_name']?.toString().trim();
      if (otherName != null &&
          otherName.isNotEmpty &&
          !isGenericTitle(otherName)) {
        return otherName;
      }

      final customerName = metadata['customer_name']?.toString().trim();
      final stationName = metadata['station_name']?.toString().trim();
      final riderName = metadata['rider_name']?.toString().trim();

      if (riderName != null &&
          riderName.isNotEmpty &&
          !isGenericTitle(riderName)) {
        return '$riderName (Rider)';
      }
      if (customerName != null &&
          customerName.isNotEmpty &&
          !isGenericTitle(customerName)) {
        return customerName;
      }
      if (stationName != null &&
          stationName.isNotEmpty &&
          !isGenericTitle(stationName)) {
        return stationName;
      }
    }

    // 3. If title is specific (not generic like "Order Delivery"), use it
    if (title != null && !isGenericTitle(title)) {
      return title!;
    }

    // 4. Order Reference ID
    if (isOrderDelivery && referenceId != null && referenceId!.isNotEmpty) {
      final ref = referenceId!.length > 8
          ? referenceId!.substring(0, 8)
          : referenceId!;
      return 'Order #${ref.toUpperCase()}';
    }

    // 5. Friendly fallback
    if (isOrderDelivery) return 'Refill Delivery Order';
    if (isCustomerSupport) return 'Customer Support';
    return 'Chat';
  }

  String get displayTitle => getDisplayTitle();

  ChatRoom copyWith({
    String? id,
    ChatRoomType? roomType,
    String? referenceId,
    ChatRoomStatus? status,
    String? ownerId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? archivedAt,
    Map<String, dynamic>? metadata,
    List<ChatParticipant>? participants,
    Message? lastMessage,
    int? unreadCount,
  }) {
    return ChatRoom(
      id: id ?? this.id,
      roomType: roomType ?? this.roomType,
      referenceId: referenceId ?? this.referenceId,
      status: status ?? this.status,
      ownerId: ownerId ?? this.ownerId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      metadata: metadata ?? this.metadata,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

// Forward declarations - will be defined in separate files
class ChatParticipant {
  final String id;
  final String roomId;
  final String userId;
  final ParticipantRole roleInRoom;
  final DateTime joinedAt;
  final DateTime? lastReadAt;
  final bool isMuted;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic>? userProfile; // Joined profile data

  ChatParticipant({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.roleInRoom,
    required this.joinedAt,
    this.lastReadAt,
    this.isMuted = false,
    this.metadata = const {},
    this.userProfile,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    // Safely extract values with null checks - extremely resilient to missing fields
    final id = json['id']?.toString() ?? 'unknown-id';
    final roomId = json['room_id']?.toString() ?? '';
    final userId = json['user_id']?.toString() ?? 'unknown-user';
    final roleInRoomStr = json['role_in_room']?.toString() ?? 'customer';
    final joinedAtStr = json['joined_at']?.toString();

    Map<String, dynamic>? profile;
    if (json['profiles'] is Map) {
      profile = Map<String, dynamic>.from(json['profiles'] as Map);
    } else if (json['profiles'] is List &&
        (json['profiles'] as List).isNotEmpty) {
      final first = (json['profiles'] as List).first;
      if (first is Map) profile = Map<String, dynamic>.from(first);
    } else if (json['userProfile'] is Map) {
      profile = Map<String, dynamic>.from(json['userProfile'] as Map);
    } else if (json['full_name'] != null || json['username'] != null) {
      profile = {
        'full_name': json['full_name'],
        'username': json['username'],
        'avatar_url': json['avatar_url'],
      };
    }

    return ChatParticipant(
      id: id,
      roomId: roomId,
      userId: userId,
      roleInRoom: ParticipantRole.fromString(roleInRoomStr),
      joinedAt: joinedAtStr != null
          ? DateTime.tryParse(joinedAtStr) ?? DateTime.now()
          : DateTime.now(),
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'].toString())
          : null,
      isMuted: json['is_muted'] as bool? ?? false,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      userProfile: profile,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'user_id': userId,
      'role_in_room': roleInRoom.value,
      'joined_at': joinedAt.toIso8601String(),
      'last_read_at': lastReadAt?.toIso8601String(),
      'is_muted': isMuted,
      'metadata': metadata,
      'userProfile': userProfile,
    };
  }
}

enum ParticipantRole {
  customer,
  rider,
  owner,
  system;

  String get value {
    switch (this) {
      case ParticipantRole.customer:
        return 'customer';
      case ParticipantRole.rider:
        return 'rider';
      case ParticipantRole.owner:
        return 'owner';
      case ParticipantRole.system:
        return 'system';
    }
  }

  static ParticipantRole fromString(String value) {
    switch (value) {
      case 'customer':
        return ParticipantRole.customer;
      case 'rider':
        return ParticipantRole.rider;
      case 'owner':
        return ParticipantRole.owner;
      case 'system':
        return ParticipantRole.system;
      default:
        return ParticipantRole.customer;
    }
  }
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  seen,
  failed;

  String get value {
    switch (this) {
      case MessageStatus.sending:
        return 'sending';
      case MessageStatus.sent:
        return 'sent';
      case MessageStatus.delivered:
        return 'delivered';
      case MessageStatus.seen:
        return 'seen';
      case MessageStatus.failed:
        return 'failed';
    }
  }

  static MessageStatus fromString(String value) {
    switch (value) {
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'seen':
        return MessageStatus.seen;
      case 'failed':
        return MessageStatus.failed;
      default:
        return MessageStatus.sent;
    }
  }
}

enum MessageType {
  text,
  image,
  system,
  quickReply,
  location,
  file;

  String get value {
    switch (this) {
      case MessageType.text:
        return 'text';
      case MessageType.image:
        return 'image';
      case MessageType.system:
        return 'system';
      case MessageType.quickReply:
        return 'quick_reply';
      case MessageType.location:
        return 'location';
      case MessageType.file:
        return 'file';
    }
  }

  static MessageType fromString(String value) {
    switch (value) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'system':
        return MessageType.system;
      case 'quick_reply':
        return MessageType.quickReply;
      case 'location':
        return MessageType.location;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }
}

class Message {
  final String id;
  final String roomId;
  final String? senderId;
  final String content;
  final MessageType messageType;
  final MessageStatus status;
  final Map<String, dynamic> metadata;
  final bool isRead;
  final List<String> readBy;
  final String? replyTo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  // Joined fields
  final Map<String, dynamic>? senderProfile;

  Message({
    required this.id,
    required this.roomId,
    this.senderId,
    required this.content,
    required this.messageType,
    this.status = MessageStatus.sent,
    this.metadata = const {},
    this.isRead = false,
    this.readBy = const [],
    this.replyTo,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.senderProfile,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    // Safely extract values with null checks - extremely resilient to missing fields
    final id = json['id']?.toString() ?? 'unknown-msg-id';
    final roomId = json['room_id']?.toString() ?? 'unknown-room-id';
    final content = json['content']?.toString() ?? '';
    final messageTypeStr = json['message_type']?.toString() ?? 'text';
    final statusStr = json['status']?.toString() ?? 'sent';
    final createdAtStr = json['created_at']?.toString();
    final updatedAtStr = json['updated_at']?.toString();

    return Message(
      id: id,
      roomId: roomId,
      senderId: json['sender_id']?.toString(),
      content: content,
      messageType: MessageType.fromString(messageTypeStr),
      status: MessageStatus.fromString(statusStr),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      isRead: json['is_read'] as bool? ?? false,
      readBy:
          (json['read_by'] as List<dynamic>?)
              ?.map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          [],
      replyTo: json['reply_to']?.toString(),
      createdAt: DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAtStr ?? '') ?? DateTime.now(),
      deletedAt: json['deleted_at'] != null
          ? DateTime.tryParse(json['deleted_at'].toString())
          : null,
      senderProfile: json['sender_profile'] as Map<String, dynamic>?,
    );
  }

  bool get isSystemMessage => messageType == MessageType.system;
  bool get isImage => messageType == MessageType.image;
  bool get isQuickReply => messageType == MessageType.quickReply;
  bool get isDeleted => deletedAt != null;

  bool isReadBy(String userId) => readBy.contains(userId);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType.value,
      'status': status.value,
      'metadata': metadata,
      'is_read': isRead,
      'read_by': readBy,
      'reply_to': replyTo,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'sender_profile': senderProfile,
    };
  }
}
