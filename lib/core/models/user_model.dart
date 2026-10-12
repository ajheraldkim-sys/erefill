class UserModel {
  final String id;
  final String email;
  final String? username;
  final String? fullName;
  final String? firstName;
  final String? lastName;
  final String? mi;
  final String? suffix;
  final String? phone;
  final String? town;
  final String? barangay;
  final String? purok;
  final String? zipCode;
  final String? avatarUrl;
  final String? stationPhotoUrl;
  final String? stationName;
  final String? vehicleType;
  final String? licenseNumber;
  final String role;
  final double averageRating;
  final String? landmark;
  final String? completeAddress;
  final double? latitude;
  final double? longitude;
  final String? preferredWaterType;
  final String? ownerId;
  final bool isSuspended;
  final String? suspendedReason;
  final DateTime updatedAt;

  UserModel({
    required this.id,
    required this.email,
    this.username,
    this.fullName,
    this.firstName,
    this.lastName,
    this.mi,
    this.suffix,
    this.phone,
    this.town,
    this.barangay,
    this.purok,
    this.zipCode,
    this.avatarUrl,
    this.stationPhotoUrl,
    this.stationName,
    this.vehicleType,
    this.licenseNumber,
    required this.role,
    this.averageRating = 0.0,
    this.landmark,
    this.completeAddress,
    this.latitude,
    this.longitude,
    this.preferredWaterType,
    this.ownerId,
    this.isSuspended = false,
    this.suspendedReason,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] ?? '',
      username: json['username'] as String?,
      fullName: json['full_name'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      mi: json['mi'] as String?,
      suffix: json['suffix'] as String?,
      phone: json['phone'] as String?,
      town: json['town'] as String?,
      barangay: json['barangay'] as String?,
      purok: json['purok'] as String?,
      zipCode: json['zip_code'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      stationPhotoUrl: json['station_photo_url'] as String?,
      stationName: json['station_name'] as String?,
      vehicleType: json['vehicle_type'] as String?,
      licenseNumber: json['license_number'] as String?,
      role: json['role'] as String? ?? 'customer',
      averageRating: json['average_rating'] is num
          ? (json['average_rating'] as num).toDouble()
          : (double.tryParse(json['average_rating']?.toString() ?? '') ?? 0.0),
      landmark: json['landmark'] as String?,
      completeAddress: json['complete_address'] as String?,
      latitude: json['latitude'] is num
          ? (json['latitude'] as num).toDouble()
          : (double.tryParse(json['latitude']?.toString() ?? '') ??
              (json['lat'] is num
                  ? (json['lat'] as num).toDouble()
                  : double.tryParse(json['lat']?.toString() ?? ''))),
      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : (double.tryParse(json['longitude']?.toString() ?? '') ??
              (json['lng'] is num
                  ? (json['lng'] as num).toDouble()
                  : double.tryParse(json['lng']?.toString() ?? ''))),
      preferredWaterType: json['preferred_water_type'] as String?,
      ownerId: json['owner_id'] as String?,
      isSuspended: json['is_suspended'] == true || json['is_suspended'] == 1,
      suspendedReason: json['suspended_reason'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? username,
    String? fullName,
    String? firstName,
    String? lastName,
    String? mi,
    String? suffix,
    String? phone,
    String? town,
    String? barangay,
    String? purok,
    String? zipCode,
    String? avatarUrl,
    String? stationPhotoUrl,
    String? stationName,
    String? vehicleType,
    String? licenseNumber,
    String? role,
    double? averageRating,
    String? landmark,
    String? completeAddress,
    double? latitude,
    double? longitude,
    String? preferredWaterType,
    String? ownerId,
    bool? isSuspended,
    String? suspendedReason,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      mi: mi ?? this.mi,
      suffix: suffix ?? this.suffix,
      phone: phone ?? this.phone,
      town: town ?? this.town,
      barangay: barangay ?? this.barangay,
      purok: purok ?? this.purok,
      zipCode: zipCode ?? this.zipCode,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      stationPhotoUrl: stationPhotoUrl ?? this.stationPhotoUrl,
      stationName: stationName ?? this.stationName,
      vehicleType: vehicleType ?? this.vehicleType,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      role: role ?? this.role,
      averageRating: averageRating ?? this.averageRating,
      landmark: landmark ?? this.landmark,
      completeAddress: completeAddress ?? this.completeAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      preferredWaterType: preferredWaterType ?? this.preferredWaterType,
      ownerId: ownerId ?? this.ownerId,
      isSuspended: isSuspended ?? this.isSuspended,
      suspendedReason: suspendedReason ?? this.suspendedReason,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'full_name': fullName,
      'first_name': firstName,
      'last_name': lastName,
      'mi': mi,
      'suffix': suffix,
      'phone': phone,
      'town': town,
      'barangay': barangay,
      'purok': purok,
      'zip_code': zipCode,
      'avatar_url': avatarUrl,
      'station_photo_url': stationPhotoUrl,
      'station_name': stationName,
      'vehicle_type': vehicleType,
      'license_number': licenseNumber,
      'role': role,
      'average_rating': averageRating,
      'landmark': landmark,
      'complete_address': completeAddress,
      'latitude': latitude,
      'longitude': longitude,
      'preferred_water_type': preferredWaterType,
      'owner_id': ownerId,
      'is_suspended': isSuspended,
      'suspended_reason': suspendedReason,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
