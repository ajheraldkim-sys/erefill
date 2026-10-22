import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants.dart';
import 'sync/realtime_hub.dart';
import 'widgets/app_cached_image.dart';

/// One entry of the admin-managed `water_types` catalog. A station sells
/// exactly one product: the refill of its registered water type.
class WaterTypeInfo {
  final String? id;
  final String name;
  final String shortName;
  final String tagline;
  final String description;
  final String badge;
  final List<String> benefits;
  final String iconKey;

  /// Admin-uploaded product photo; the icon stands in when it's missing.
  final String? photoUrl;
  final int sortOrder;
  final bool isActive;

  const WaterTypeInfo({
    this.id,
    required this.name,
    required this.shortName,
    this.tagline = '',
    this.description = '',
    this.badge = '',
    this.benefits = const [],
    this.iconKey = WaterTypes.defaultIconKey,
    this.photoUrl,
    this.sortOrder = 0,
    this.isActive = true,
  });

  IconData get icon => WaterTypes.iconFor(iconKey);
  Color get color => WaterTypes.colorFor(iconKey);

  WaterTypeInfo copyWith({
    String? id,
    String? name,
    String? shortName,
    String? tagline,
    String? description,
    String? badge,
    List<String>? benefits,
    String? iconKey,
    String? photoUrl,
    int? sortOrder,
    bool? isActive,
  }) =>
      WaterTypeInfo(
        id: id ?? this.id,
        name: name ?? this.name,
        shortName: shortName ?? this.shortName,
        tagline: tagline ?? this.tagline,
        description: description ?? this.description,
        badge: badge ?? this.badge,
        benefits: benefits ?? this.benefits,
        iconKey: iconKey ?? this.iconKey,
        photoUrl: photoUrl ?? this.photoUrl,
        sortOrder: sortOrder ?? this.sortOrder,
        isActive: isActive ?? this.isActive,
      );

  factory WaterTypeInfo.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final short = json['short_name']?.toString().trim() ?? '';
    return WaterTypeInfo(
      id: json['id']?.toString(),
      name: name,
      shortName: short.isNotEmpty ? short : WaterTypes.shortNameFor(name),
      tagline: json['tagline']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      badge: json['badge']?.toString() ?? '',
      benefits: (json['benefits'] as List?)
              ?.map((b) => b.toString())
              .where((b) => b.trim().isNotEmpty)
              .toList() ??
          const [],
      iconKey: json['icon_key']?.toString() ?? WaterTypes.defaultIconKey,
      photoUrl: switch (json['photo_url']?.toString().trim()) {
        final url? when url.isNotEmpty => url,
        _ => null,
      },
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'short_name': shortName,
        'tagline': tagline,
        'description': description,
        'badge': badge,
        'benefits': benefits,
        'icon_key': iconKey,
        'photo_url': photoUrl,
        'sort_order': sortOrder,
        'is_active': isActive,
      };
}

/// Water type catalog loaded from Supabase (`water_types`), with the last
/// successful load cached on the device for offline starts.
class WaterTypes {
  static const table = 'water_types';
  static const defaultIconKey = 'water_drop';
  static const _cacheKey = 'water_types_cache_v1';

  /// Icons an admin can pick for a water type.
  static const iconOptions = <String, IconData>{
    'water_drop': Icons.water_drop_rounded,
    'spa': Icons.spa_rounded,
    'science': Icons.science_rounded,
    'eco': Icons.eco_rounded,
    'filter': Icons.filter_alt_rounded,
    'local_drink': Icons.local_drink_rounded,
    'bolt': Icons.bolt_rounded,
    'ac_unit': Icons.ac_unit_rounded,
  };

  static const _iconColors = <String, Color>{
    'water_drop': AppUi.bluePrimary,
    'spa': AppUi.accentGreen,
    'science': AppUi.accentCyan,
    'eco': AppUi.accentGreen,
    'filter': AppUi.bluePrimaryDark,
    'local_drink': AppUi.bluePrimary,
    'bolt': AppUi.warningFg,
    'ac_unit': AppUi.accentCyan,
  };

  static IconData iconFor(String? key) =>
      iconOptions[key] ?? Icons.water_drop_rounded;

  static Color colorFor(String? key) => _iconColors[key] ?? AppUi.bluePrimary;

  /// Every catalog entry, including inactive ones (admin views).
  static final ValueNotifier<List<WaterTypeInfo>> catalog =
      ValueNotifier(const []);

  static Future<List<WaterTypeInfo>>? _inFlight;
  static bool _restoredCache = false;

  /// Active types offered at registration and as customer preferences.
  static List<WaterTypeInfo> get all =>
      catalog.value.where((t) => t.isActive).toList();

  /// First active type, used as a form default.
  static WaterTypeInfo? get defaultType {
    final active = all;
    return active.isEmpty ? null : active.first;
  }

  static StreamSubscription<RealtimeEvent>? _realtimeSub;

  /// Loads the catalog. Concurrent callers share one request; failures keep
  /// the cached catalog. Subscribes to Supabase Realtime so admin updates
  /// propagate to listeners immediately.
  static Future<List<WaterTypeInfo>> load({
    SupabaseClient? client,
    bool force = false,
  }) {
    _ensureRealtimeSub();
    if (!force && catalog.value.isNotEmpty && _inFlight == null) {
      return Future.value(catalog.value);
    }
    return _inFlight ??= _fetch(client).whenComplete(() => _inFlight = null);
  }

  static void _ensureRealtimeSub() {
    if (_realtimeSub != null) return;
    try {
      _realtimeSub = RealtimeHub.instance.listen(
        const TableWatch(table),
        (event) {
          unawaited(load(force: true));
        },
      );
    } catch (e) {
      debugPrint('WaterTypes realtime listener error: $e');
    }
  }

  /// Cancels the realtime subscription (for testing).
  @visibleForTesting
  static void cancelRealtimeSubscription() {
    _realtimeSub?.cancel();
    _realtimeSub = null;
  }

  static Future<List<WaterTypeInfo>> _fetch(SupabaseClient? client) async {
    await _restoreCache();
    try {
      final rows = await (client ?? Supabase.instance.client)
          .from(table)
          .select()
          .order('sort_order')
          .order('name');
      final types = (rows as List)
          .whereType<Map>()
          .map((r) => WaterTypeInfo.fromJson(Map<String, dynamic>.from(r)))
          .where((t) => t.name.isNotEmpty)
          .toList();

      // Evict old photo URLs from cache if they changed or were removed
      for (final oldType in catalog.value) {
        if (oldType.photoUrl == null) continue;
        final matching = types
            .where((t) => t.id == oldType.id || t.name == oldType.name);
        if (matching.isEmpty || matching.first.photoUrl != oldType.photoUrl) {
          unawaited(AppCachedImage.evict(oldType.photoUrl));
        }
      }

      catalog.value = List.unmodifiable(types);
      unawaited(_saveCache(types));
    } catch (e) {
      debugPrint('WaterTypes.load error: $e');
    }
    return catalog.value;
  }

  static Future<void> _restoreCache() async {
    if (_restoredCache || catalog.value.isNotEmpty) return;
    _restoredCache = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || catalog.value.isNotEmpty) return;
      final decoded = jsonDecode(raw) as List;
      catalog.value = List.unmodifiable(
        decoded
            .whereType<Map>()
            .map((r) => WaterTypeInfo.fromJson(Map<String, dynamic>.from(r))),
      );
    } catch (e) {
      debugPrint('WaterTypes cache restore error: $e');
    }
  }

  static Future<void> _saveCache(List<WaterTypeInfo> types) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(types.map((t) => t.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('WaterTypes cache save error: $e');
    }
  }

  /// Replaces the in-memory catalog; for tests and admin edits.
  @visibleForTesting
  static void setCatalog(List<WaterTypeInfo> types) {
    catalog.value = List.unmodifiable(types);
  }

  /// "Mineral Water" -> "Mineral".
  static String shortNameFor(String name) {
    final trimmed = name.trim();
    final stripped = trimmed.replaceFirst(
      RegExp(r'\s+water$', caseSensitive: false),
      '',
    );
    return stripped.isNotEmpty ? stripped : trimmed;
  }

  /// Resolves a stored water type name (or product category/name) to its
  /// catalog entry. Unknown values get a plain entry carrying that name.
  static WaterTypeInfo byName(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    final types = catalog.value;
    if (normalized.isNotEmpty) {
      for (final type in types) {
        if (type.name.toLowerCase() == normalized ||
            type.shortName.toLowerCase() == normalized) {
          return type;
        }
      }
      for (final type in types) {
        if (normalized.contains(type.shortName.toLowerCase())) return type;
      }
      final name = (value ?? '').trim();
      return WaterTypeInfo(name: name, shortName: shortNameFor(name));
    }
    return defaultType ??
        const WaterTypeInfo(name: 'Water refill', shortName: 'Refill');
  }
}
