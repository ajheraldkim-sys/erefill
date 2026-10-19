import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/user_provider.dart';
import '../../core/providers/notification_provider.dart';
import '../../core/widgets/brand/hero_header.dart';
import '../../core/widgets/brand/axo_states.dart';
import 'models/chat_room.dart';
import 'services/chat_service.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/routing/app_navigation.dart';

/// Unified Inbox Screen - Updated to use new room-based chat system
/// This replaces the legacy message-based inbox with room-based architecture
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedTab = 0; // 0 = All, 1 = Orders, 2 = Support
  List<ChatRoom>? _initialRooms;

  @override
  void initState() {
    super.initState();
    _allRoomsStream = _chatService.getChatRoomsForUser().asBroadcastStream();
    _loadInitialCache();
  }

  Future<void> _loadInitialCache() async {
    final cached = await _chatService.getCachedRooms();
    if (mounted) {
      setState(() {
        _initialRooms = cached;
      });
    }
  }

  Stream<List<ChatRoom>>? _allRoomsStream;
  final Set<String> _selectedRoomIds = {};
  List<ChatRoom> _allRooms =
      []; // Store currently visible rooms for selection logic and bulk actions

  String _getRoomTitle(ChatRoom room) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    String? myRole;
    try {
      myRole = context.read<UserProvider>().user?.role;
    } catch (_) {}
    return room.getDisplayTitle(currentUserId: myId, currentUserRole: myRole);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final colorScheme = Theme.of(context).colorScheme;
    if (myId == null) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: Center(
          child: Text(
            'Please sign in to view messages',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppUi.textSecondaryOf(context),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: _selectedRoomIds.isNotEmpty
                ? '${_selectedRoomIds.length} selected'
                : 'Messages',
            subtitle: _selectedRoomIds.isNotEmpty
                ? 'Choose an action'
                : 'Orders and support conversations',
            actions: _selectedRoomIds.isNotEmpty
                ? [
                    IconButton(
                      icon: Icon(
                        Icons.select_all_rounded,
                        color: AppUi.textPrimaryOf(context),
                      ),
                      onPressed: _selectAllRooms,
                    ),
                    IconButton(
                      icon: Icon(
                        _selectedTab == 3
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        color: AppUi.textPrimaryOf(context),
                      ),
                      tooltip: _selectedTab == 3 ? 'Restore' : 'Archive',
                      onPressed: _handleArchiveOrRestoreRooms,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppUi.textPrimaryOf(context),
                      ),
                      onPressed: () => setState(() => _selectedRoomIds.clear()),
                    ),
                  ]
                : [
                    IconButton(
                      icon: Icon(
                        Icons.done_all_rounded,
                        color: AppUi.brandOf(context),
                      ),
                      onPressed: _markAllAsRead,
                    ),
                  ],
            bottom: Material(
              color: AppUi.surfaceOf(context),
              borderRadius: AppUi.pillRadius,
              elevation: 0,
              child: TextField(
                controller: _searchController,
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
                style: TextStyle(
                  color: AppUi.textPrimaryOf(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Search conversations',
                  hintStyle: TextStyle(
                    color: AppUi.textSecondaryOf(context),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppUi.textSecondaryOf(context),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: AppUi.pillRadius,
                    borderSide: BorderSide(color: AppUi.borderOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppUi.pillRadius,
                    borderSide: BorderSide(color: AppUi.borderOf(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppUi.pillRadius,
                    borderSide: const BorderSide(
                      color: AppUi.bluePrimary,
                      width: 1.5,
                    ),
                  ),
                  filled: true,
                  fillColor: AppUi.surfaceOf(context),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppUi.screenPadding,
              AppUi.spacingSm,
              AppUi.screenPadding,
              AppUi.spacingLg,
            ),
            color: colorScheme.surface,
            child: _buildCategoryTabs(),
          ),
          const Divider(height: 1, color: AppUi.bluePale),
          Expanded(
            child: Container(
              color: AppUi.pageBgOf(context),
              child: _buildChatRoomsList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final colorScheme = Theme.of(context).colorScheme;
    final tabs = ['All Messages', 'Order Chats', 'Support', 'Archived'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedTab == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                if (_selectedTab != index) {
                  setState(() {
                    _selectedTab = index;
                    _selectedRoomIds
                        .clear(); // Clear selection when switching tabs
                  });
                }
              },
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppUi.bluePrimary : colorScheme.surface,
                  borderRadius: AppUi.controlRadius,
                  border: Border.all(
                    color: isSelected
                        ? AppUi.bluePrimary
                        : AppUi.borderOf(context),
                  ),
                ),
                child: Text(
                  tabs[index],
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildChatRoomsList() {
    return StreamBuilder<List<ChatRoom>>(
      stream: _allRoomsStream,
      initialData: _initialRooms,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            (_initialRooms == null || _initialRooms!.isEmpty)) {
          return SkeletonList(
            itemDelegate: _buildSkeletonItem,
            padding: const EdgeInsets.all(24),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppUi.textDisabled,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sync disconnected. Tap to retry.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        final allFetchedRooms = snapshot.data ?? [];

        // 1. Filter by Tab
        List<ChatRoom> tabRooms;
        switch (_selectedTab) {
          case 1:
            tabRooms = allFetchedRooms
                .where((r) => r.isOrderDelivery && !r.isArchived)
                .toList();
            break;
          case 2:
            tabRooms = allFetchedRooms
                .where((r) => r.isCustomerSupport && !r.isArchived)
                .toList();
            break;
          case 3:
            tabRooms = allFetchedRooms.where((r) => r.isArchived).toList();
            break;
          default:
            tabRooms = allFetchedRooms.where((r) => !r.isArchived).toList();
        }

        // 2. Filter by Search Query
        final filteredRooms = _searchQuery.isEmpty
            ? tabRooms
            : tabRooms.where((room) {
                final title = _getRoomTitle(room).toLowerCase();
                final lastMsg = room.lastMessage?.content.toLowerCase() ?? '';
                return title.contains(_searchQuery) ||
                    lastMsg.contains(_searchQuery);
              }).toList();

        // Update _allRooms with current filtered results for selection logic
        _allRooms = filteredRooms;

        if (filteredRooms.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          itemCount: filteredRooms.length,
          itemBuilder: (context, index) =>
              _buildChatRoomTile(filteredRooms[index]),
        );
      },
    );
  }

  Widget _buildChatRoomTile(ChatRoom room) {
    final hasUnread = (room.unreadCount ?? 0) > 0;
    final isSelected = _selectedRoomIds.contains(room.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        border: Border.all(
          color: isSelected ? AppUi.bluePrimary : AppUi.borderOf(context),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onLongPress: () => _toggleRoomSelection(room.id),
        onTap: _selectedRoomIds.isNotEmpty
            ? () => _toggleRoomSelection(room.id)
            : () => _openChat(room),
        borderRadius: AppUi.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildAvatar(room),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _getRoomTitle(room),
                            style: TextStyle(
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w700,
                              fontSize: 15,
                              color: AppUi.textPrimaryOf(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatTime(room.updatedAt),
                          style: TextStyle(
                            color: hasUnread
                                ? AppUi.brandOf(context)
                                : AppUi.textSecondaryOf(context),
                            fontSize: 11,
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.lastMessage != null
                                ? (room.lastMessage!.isSystemMessage
                                      ? 'Update: ${room.lastMessage!.content}'
                                      : room.lastMessage!.content)
                                : 'Start a conversation...',
                            style: TextStyle(
                              color: hasUnread
                                  ? AppUi.textPrimaryOf(context)
                                  : AppUi.textSecondaryOf(context),
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(
                              color: AppUi.bluePrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ChatRoom room) {
    final title = _getRoomTitle(room).trim();
    final isPerson = !ChatRoom.isGenericTitle(title) && title.isNotEmpty;

    // Check if any participant has an avatar_url
    String? avatarUrl;
    if (room.participants != null) {
      for (final p in room.participants!) {
        final profile = p.userProfile;
        if (profile?['avatar_url'] != null &&
            profile!['avatar_url'].toString().isNotEmpty) {
          avatarUrl = profile['avatar_url'].toString();
          break;
        }
      }
    }

    if (avatarUrl != null) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(avatarUrl),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (isPerson) {
      final initials = title
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => s[0].toUpperCase())
          .take(2)
          .join();
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppUi.bluePrimary.withValues(alpha: 0.12),
          borderRadius: AppUi.cardRadius,
          border: Border.all(
            color: AppUi.bluePrimary.withValues(alpha: 0.25),
          ),
        ),
        child: Center(
          child: Text(
            initials.isNotEmpty ? initials : '?',
            style: TextStyle(
              color: AppUi.brandOf(context),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    IconData icon;
    Color color;
    if (room.isOrderDelivery) {
      icon = Icons.local_shipping_rounded;
      color = AppColors.brandPrimary;
    } else if (room.isCustomerSupport) {
      icon = Icons.support_agent_rounded;
      color = AppColors.statusCompleted;
    } else if (room.isRiderDispatch) {
      icon = Icons.two_wheeler_rounded;
      color = AppColors.statusOutForDelivery;
    } else {
      icon = Icons.chat_bubble_rounded;
      color = AppUi.textSecondaryOf(context);
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppUi.cardRadius,
      ),
      child: Center(child: Icon(icon, color: color, size: 24)),
    );
  }

  Widget _buildEmptyState() {
    late final String title;
    late final String message;
    switch (_selectedTab) {
      case 1:
        title = 'No order chats yet';
        message =
            'Conversations with your water station or delivery rider will appear here automatically when you place a refill order.';
        break;
      case 2:
        title = 'No support conversations';
        message =
            'Support messages with station staff will appear here when you reach out for help.';
        break;
      default:
        title = 'No conversations yet';
        message =
            'Conversations with water stations and riders appear here once an order is placed or when you message a station.';
    }

    return AxoEmptyState(
      pose: AxoPose.thinking,
      compact: true,
      title: title,
      message: message,
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    if (dateTime.day == now.day &&
        dateTime.month == now.month &&
        dateTime.year == now.year) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    return '${dateTime.day}/${dateTime.month}';
  }

  void _openChat(ChatRoom room) {
    _chatService.markAsRead(room.id);
    try {
      context.read<NotificationProvider>().refreshCounts();
    } catch (_) {}
    context.openChat(
      roomId: room.id,
      roomTitle: _getRoomTitle(room),
      roomType: room.roomType,
    );
  }

  void _toggleRoomSelection(String roomId) {
    setState(() {
      if (_selectedRoomIds.contains(roomId)) {
        _selectedRoomIds.remove(roomId);
      } else {
        _selectedRoomIds.add(roomId);
        HapticFeedback.lightImpact();
      }
    });
  }

  void _selectAllRooms() {
    setState(() {
      if (_selectedRoomIds.length == _allRooms.length) {
        _selectedRoomIds.clear();
      } else {
        _selectedRoomIds.addAll(_allRooms.map((r) => r.id));
        HapticFeedback.mediumImpact();
      }
    });
  }

  Future<void> _handleArchiveOrRestoreRooms() async {
    final isArchivedTab = _selectedTab == 3;
    final count = _selectedRoomIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isArchivedTab ? 'Restore Conversations' : 'Archive Conversations',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          isArchivedTab
              ? 'Restore $count conversation thread(s) back to your active inbox?'
              : 'Archive $count conversation thread(s)? They will be hidden from your active inbox and moved to the Archived tab.',
        ),
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppUi.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isArchivedTab ? 'Restore' : 'Archive',
              style: TextStyle(
                color: isArchivedTab ? AppUi.brandOf(context) : AppColors.uiError,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final roomIdsToProcess = _selectedRoomIds.toList();
      for (final id in roomIdsToProcess) {
        if (isArchivedTab) {
          await _chatService.unarchiveChatRoom(id);
        } else {
          await _chatService.archiveChatRoom(id);
        }
      }
      setState(() => _selectedRoomIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArchivedTab
                  ? '$count conversation(s) restored to inbox.'
                  : '$count conversation(s) archived.',
            ),
            backgroundColor: AppUi.accentGreen,
          ),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    final futures = _allRooms
        .where((room) => (room.unreadCount ?? 0) > 0)
        .map((room) => _chatService.markAsRead(room.id));
    await Future.wait(futures);
    if (mounted) {
      try {
        context.read<NotificationProvider>().refreshCounts();
      } catch (_) {}
    }
  }

  Widget _buildSkeletonItem(BuildContext context, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          const Skeleton(height: 52, width: 52, borderRadius: 16),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(height: 14, width: 140),
                const SizedBox(height: 8),
                const Skeleton(height: 12, width: double.infinity),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
