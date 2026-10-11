class QuickReply {
  final String id;
  final String riderId;
  final String label;
  final String messageText;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  QuickReply({
    required this.id,
    required this.riderId,
    required this.label,
    required this.messageText,
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory QuickReply.fromJson(Map<String, dynamic> json) {
    return QuickReply(
      id: json['id'] as String,
      riderId: json['rider_id'] as String,
      label: json['label'] as String,
      messageText: json['message_text'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rider_id': riderId,
      'label': label,
      'message_text': messageText,
      'sort_order': sortOrder,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'rider_id': riderId,
      'label': label,
      'message_text': messageText,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }

  QuickReply copyWith({
    String? id,
    String? riderId,
    String? label,
    String? messageText,
    int? sortOrder,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuickReply(
      id: id ?? this.id,
      riderId: riderId ?? this.riderId,
      label: label ?? this.label,
      messageText: messageText ?? this.messageText,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Pre-defined quick replies for new riders
  static List<Map<String, dynamic>> get defaultQuickReplies {
    return [
      {
        'label': 'I\'m 5 minutes away',
        'message_text':
            'Hi! I\'m about 5 minutes away with your order. Please get ready!',
        'sort_order': 1,
      },
      {
        'label': 'I have arrived',
        'message_text':
            'I\'ve arrived at your location. Please come out to receive your order.',
        'sort_order': 2,
      },
      {
        'label': 'Can\'t find house',
        'message_text':
            'I\'m having trouble finding your exact house. Can you provide more specific directions?',
        'sort_order': 3,
      },
      {
        'label': 'Order delivered',
        'message_text':
            'Your order has been delivered. Thank you for choosing us!',
        'sort_order': 4,
      },
      {
        'label': 'Running late',
        'message_text':
            'Sorry, I\'m running a bit late due to traffic. I\'ll be there soon!',
        'sort_order': 5,
      },
    ];
  }

  @override
  String toString() =>
      'QuickReply(id: $id, label: $label, message: $messageText)';
}
