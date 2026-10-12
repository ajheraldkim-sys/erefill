import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/providers/user_provider.dart';
import '../../core/widgets/brand/hero_header.dart';
import '../../core/widgets/skeleton.dart';
import '../../../core/routing/app_navigation.dart';
import 'models/chat_room.dart';
import 'models/quick_reply.dart';
import 'services/chat_service.dart';
import 'utils/chat_identity_resolver.dart';

/// Enhanced ChatScreen with room-based architecture
/// Supports all roles: Customer, Rider, Owner
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.roomId,
    this.roomTitle,
    this.roomType,
    // Legacy parameters for backward compatibility
    this.receiverId,
    this.receiverName,
    this.ownerId,
  });

  // New room-based parameters
  final String? roomId;
  final String? roomTitle;
  final ChatRoomType? roomType;

  // Legacy parameters (for backward compatibility)
  final String? receiverId;
  final String? receiverName;
  final String? ownerId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  final ImagePicker _picker = ImagePicker();
  List<QuickReply> _quickReplies = [];
  Map<String, dynamic>? _room;
  Map<String, dynamic>? _orderContext;
  String? _assignedRiderId;
  String? _otherUserName;
  final Set<String> _selectedMessageIds = {}; // For multi-select
  List<Message> _allMessages = []; // For "Select All"
  Stream<List<Message>>? _messagesStream;

  @override
  void initState() {
    super.initState();
    if (widget.roomId != null) {
      _messagesStream = _chatService
          .getMessagesForRoom(widget.roomId!)
          .asBroadcastStream();
    }
    _loadQuickReplies();
    _loadRoom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRoom() async {
    if (widget.roomId != null) {
      final room = await _chatService.getChatRoom(widget.roomId!);
      if (mounted && room != null) {
        final title = room.displayTitle;
        setState(() {
          _room = room.toJson();
          if (!ChatRoom.isGenericTitle(title)) {
            _otherUserName = title;
          }
          _assignedRiderId = room.participants
              ?.firstWhere(
                (p) => p.roleInRoom == ParticipantRole.rider,
                orElse: () => ChatParticipant(
                  id: '',
                  roomId: '',
                  userId: '',
                  roleInRoom: ParticipantRole.system,
                  joinedAt: DateTime.now(),
                ),
              )
              .userId;
        });

        // Also fetch other participant profile to guarantee actual user name
        _chatService.getOtherParticipant(widget.roomId!).then((other) {
          if (!mounted || other == null) return;
          final profile = other['profiles'] as Map<String, dynamic>?;
          final name = profile?['full_name']?.toString().trim() ??
              other['full_name']?.toString().trim() ??
              profile?['username']?.toString().trim();
          if (name != null &&
              name.isNotEmpty &&
              !ChatRoom.isGenericTitle(name)) {
            setState(() => _otherUserName = name);
          }
        });

        if (room.isOrderDelivery) {
          _loadOrderContext();
        }
        // Mark as read when opening
        _chatService.markAsRead(widget.roomId!);
      }
    }
  }

  Future<void> _loadOrderContext() async {
    final orderId = _room?['reference_id'];
    if (orderId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('orders')
          .select(
              'status, station_name, customer_name, total_amount, assigned_rider_id')
          .eq('id', orderId)
          .single();
      if (mounted) {
        setState(() {
          _orderContext = data;
          _assignedRiderId ??= data['assigned_rider_id'];
        });
      }
    } catch (e) {
      debugPrint('Error loading order context: $e');
    }
  }

  void _openMap() {
    final orderId = _room?['reference_id'];
    if (orderId == null || _assignedRiderId == null) return;
    HapticFeedback.mediumImpact();
    context.openOrderTrackingMap(orderId: orderId, riderId: _assignedRiderId);
  }

  Future<void> _loadQuickReplies() async {
    try {
      final replies = await _chatService.getQuickReplies();
      if (mounted) {
        setState(() => _quickReplies = replies);
      }
    } catch (e) {
      // Quick replies are optional, ignore errors
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      if (widget.roomId != null) {
        await _chatService.sendMessage(roomId: widget.roomId!, content: text);
      } else if (widget.ownerId != null) {
        final customerId = Supabase.instance.client.auth.currentUser?.id;
        if (customerId == null) {
          throw Exception('Sign in to send messages.');
        }
        final room = await _chatService.createSupportChatRoom(
          customerId: customerId,
          ownerId: widget.ownerId!,
          stationName: widget.receiverName,
        );
        if (!mounted) return;
        await _chatService.sendMessage(roomId: room.id, content: text);
      } else {
        throw Exception('Chat room is not available.');
      }
      _messageController.clear();
      _scrollToBottom(animate: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (_sending || widget.roomId == null) return;

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Send Photo',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE0F2FE),
                  child: Icon(Icons.camera_alt_rounded, color: AppUi.bluePrimary),
                ),
                title: const Text('Take a Photo', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Use camera to capture image'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF1F5F9),
                  child: Icon(Icons.photo_library_rounded, color: AppUi.bluePrimary),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Select an existing photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 65,
      maxWidth: 1400,
    );
    if (image == null) return;

    setState(() => _sending = true);
    try {
      final file = File(image.path);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      await _chatService.sendImageMessage(
        roomId: widget.roomId!,
        file: file,
        fileName: fileName,
      );
      _scrollToBottom(animate: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image upload failed: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom({bool animate = false}) {
    if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    }
  }

  Widget _buildQuickReplyChip(String text, {bool isCustom = false}) {
    return InkWell(
      onTap: _sending
          ? null
          : () {
              HapticFeedback.lightImpact();
              _messageController.text = text;
              _send();
            },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCustom ? AppUi.blueSoft : AppUi.surfaceOf(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isCustom ? AppUi.blueBorder : AppUi.borderOf(context),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isCustom ? AppUi.bluePrimary : const Color(0xFF334155),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String get _displayTitle {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    String? myRole;
    try {
      myRole = context.read<UserProvider>().user?.role;
    } catch (_) {}

    if (_room != null) {
      final roomObj = ChatRoom.fromJson(_room!);
      final resolved = ChatIdentityResolver.resolveRoomDisplayTitle(
        room: roomObj,
        currentUserId: myId,
        currentUserRole: myRole,
        orderContext: _orderContext,
      );
      if (!ChatRoom.isGenericTitle(resolved)) {
        return resolved;
      }
    }

    if (widget.roomTitle != null &&
        !ChatRoom.isGenericTitle(widget.roomTitle)) {
      return widget.roomTitle!;
    }
    if (_otherUserName != null && _otherUserName!.isNotEmpty) {
      return _otherUserName!;
    }
    if (widget.receiverName != null &&
        widget.receiverName!.isNotEmpty &&
        !ChatRoom.isGenericTitle(widget.receiverName)) {
      return widget.receiverName!;
    }
    if (_orderContext?['station_name'] != null) {
      final st = _orderContext!['station_name'].toString().trim();
      if (st.isNotEmpty) return st;
    }
    if (_orderContext?['customer_name'] != null) {
      final cust = _orderContext!['customer_name'].toString().trim();
      if (cust.isNotEmpty) return cust;
    }
    return widget.roomTitle ?? 'Refill Chat';
  }

  String get _chatSubtitle {
    if (_selectedMessageIds.isNotEmpty) return 'Choose an action';
    String? myRole;
    try {
      myRole = context.read<UserProvider>().user?.role;
    } catch (_) {}

    ChatRoom? roomObj;
    if (_room != null) {
      roomObj = ChatRoom.fromJson(_room!);
    }
    return ChatIdentityResolver.resolveRoomSubtitle(
      room: roomObj,
      currentUserRole: myRole,
      orderContext: _orderContext,
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) {
      return const Scaffold(body: Center(child: Text('Please sign in')));
    }

    // Check if we have valid room parameters
    if (widget.roomId == null &&
        (widget.receiverId == null || widget.ownerId == null)) {
      return const Scaffold(
        body: Center(child: Text('Invalid chat configuration')),
      );
    }

    return PopScope(
      canPop: _selectedMessageIds.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedMessageIds.isNotEmpty) {
          setState(() => _selectedMessageIds.clear());
        }
      },
      child: Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: Column(
          children: [
            TabScreenHeroHeader(
              leading: IconButton(
                onPressed: () {
                  if (_selectedMessageIds.isNotEmpty) {
                    setState(() => _selectedMessageIds.clear());
                  } else {
                    context.popRoute();
                  }
                },
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              title: _selectedMessageIds.isNotEmpty
                  ? '${_selectedMessageIds.length} selected'
                  : _displayTitle,
              subtitle: _chatSubtitle,
              actions: _selectedMessageIds.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(
                          Icons.select_all_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _selectAllMessages,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _deleteSelectedMessages,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () =>
                            setState(() => _selectedMessageIds.clear()),
                      ),
                    ]
                  : [
                      if (_room?['room_type'] == 'order_delivery' &&
                          _assignedRiderId != null)
                        IconButton(
                          icon: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                          ),
                          onPressed: _openMap,
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                        ),
                        onSelected: (val) {
                          if (val == 'clear') _clearChat();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'clear',
                            child: Text('Clear history'),
                          ),
                        ],
                      ),
                    ],
            ),
            if (_room?['room_type'] == 'order_delivery' &&
                _orderContext != null)
              _buildOrderContextBar(),
            Expanded(
              child: Container(
                color: AppUi.pageBgOf(context),
                child: widget.roomId != null
                    ? _buildRoomMessages(myId)
                    : _buildLegacyMessages(myId),
              ),
            ),
            _buildQuickInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickInputArea() {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final bottomPadding = bottomInset > 0
        ? AppUi.spacingSm
        : (mediaQuery.padding.bottom + AppUi.spacingSm);

    return Container(
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(top: BorderSide(color: AppUi.borderOf(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Suggestions/Quick Replies
          if (widget.roomId != null) _buildSuggestionsBar(),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppUi.screenPadding,
              vertical: AppUi.spacingSm,
            ),
            child: Row(
              children: [
                _buildActionButton(Icons.add_rounded, _sendImage),
                AppUi.hGapMd,
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: AppUi.controlRadius,
                      border: Border.all(color: AppUi.borderOf(context)),
                    ),
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: const TextStyle(
                          color: AppUi.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                AppUi.hGapMd,
                _sending
                    ? const SizedBox(
                        width: 44,
                        height: 44,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _buildSendButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsBar() {
    final replies = _quickReplies.isNotEmpty
        ? _quickReplies.map((r) => r.label).toList()
        : _getQuickReplies();
    if (replies.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: replies.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _buildQuickReplyChip(
            replies[index],
            isCustom: _quickReplies.isNotEmpty,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: _sending ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppUi.controlRadius,
          border: Border.all(color: AppUi.borderOf(context)),
        ),
        child: Icon(icon, color: AppUi.textSecondaryOf(context), size: 20),
      ),
    );
  }

  Widget _buildSendButton() {
    return InkWell(
      onTap: _send,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: AppUi.controlRadius,
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildRoomMessages(String myId) {
    return StreamBuilder<List<Message>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(itemCount: 5);
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        _allMessages = snapshot.data ?? [];
        if (_allMessages.isEmpty) return _buildEmptyConversation();

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          itemCount: _allMessages.length,
          itemBuilder: (context, index) {
            final msg = _allMessages[index];
            final isMine = msg.senderId == myId;
            if (msg.isSystemMessage) return _buildSystemMessage(msg);
            return _buildUserMessage(msg, isMine);
          },
        );
      },
    );
  }

  Widget _buildEmptyConversation() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: AppUi.textDisabled,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Secure Channel Active',
            style: TextStyle(
              color: AppUi.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(Message msg) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppUi.surfaceRaisedOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppUi.borderOf(context)),
        ),
        child: Text(
          msg.content,
          style: TextStyle(
            fontSize: 10,
            color: AppUi.textSecondaryOf(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildUserMessage(Message msg, bool isMine) {
    final isSelected = _selectedMessageIds.contains(msg.id);
    final myId = Supabase.instance.client.auth.currentUser?.id;
    String? myRole;
    try {
      myRole = context.read<UserProvider>().user?.role;
    } catch (_) {}

    ParticipantRole? senderRole;
    Map<String, dynamic>? senderProfile = msg.senderProfile;

    if (_room != null && _room!['participants'] is List) {
      final pList = _room!['participants'] as List;
      for (final p in pList) {
        if (p is Map && (p['user_id'] == msg.senderId || p['id'] == msg.senderId)) {
          if (p['role_in_room'] != null) {
            senderRole = ParticipantRole.fromString(p['role_in_room'].toString());
          }
          senderProfile ??= (p['profiles'] as Map<String, dynamic>?) ??
              (p['userProfile'] as Map<String, dynamic>?);
          break;
        }
      }
    }

    final senderDisplayName = ChatIdentityResolver.resolveSenderName(
      senderId: msg.senderId,
      currentUserId: myId,
      currentUserRole: myRole,
      senderRole: senderRole,
      senderProfile: senderProfile,
      roomMetadata: _room?['metadata'] as Map<String, dynamic>?,
      orderContext: _orderContext,
      roomType: widget.roomType ??
          (_room != null ? ChatRoomType.fromString(_room!['room_type']?.toString() ?? '') : null),
      isSystemMessage: msg.isSystemMessage,
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  senderDisplayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
              ),
            InkWell(
              onLongPress: () => _toggleSelection(msg.id),
              onTap: _selectedMessageIds.isNotEmpty
                ? () => _toggleSelection(msg.id)
                : null,
              borderRadius: AppUi.cardRadius,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppUi.bluePrimary.withValues(alpha: 0.1)
                      : isMine
                      ? AppUi.bluePrimary
                      : AppUi.surfaceOf(context),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMine ? 16 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 16),
                  ),
                  border: isSelected
                      ? Border.all(color: AppUi.bluePrimary, width: 1.5)
                      : !isMine
                      ? Border.all(color: AppUi.borderOf(context))
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.04,
                      ),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (msg.isImage && msg.metadata['image_url'] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            msg.metadata['image_url'],
                            width: 220,
                            fit: BoxFit.cover,
                            cacheWidth: 440,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_rounded),
                          ),
                        ),
                      ),
                    Text(
                      msg.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: isMine ? Colors.white : AppUi.textPrimaryOf(context),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg.createdAt),
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppUi.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 12,
                    color: msg.isRead ? AppUi.bluePrimary : AppUi.textMuted,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getQuickReplies() {
    if (_room?['room_type'] == 'order_delivery') {
      return [
        'Where are you now?',
        'ETA please?',
        'I am at the gate',
        'Leave at the door',
        'Ring the doorbell',
      ];
    } else {
      return [
        'What are your hours?',
        'Is my order ready?',
        'Do you have stock?',
        'Thank you!',
      ];
    }
  }

  Widget _buildOrderContextBar() {
    final status = _orderContext?['status'] ?? 'unknown';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppUi.surfaceRaisedOf(context),
        borderRadius: AppUi.cardRadius,
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delivery_dining_rounded,
              color: AppUi.bluePrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatStatus(status),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                Text(
                  _orderContext?['station_name'] ?? 'Loading...',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_assignedRiderId != null)
            TextButton.icon(
              onPressed: _openMap,
              icon: const Icon(Icons.map_rounded, size: 16),
              label: const Text(
                'TRACK',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppUi.bluePrimary,
                backgroundColor: AppUi.surfaceOf(context),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatStatus(String s) {
    switch (s) {
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'assigned_to_rider':
        return 'Assigned to Rider';
      case 'out_for_delivery':
        return 'Out for Delivery';
      default:
        return s.isEmpty ? 'Processing' : s[0].toUpperCase() + s.substring(1);
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _toggleSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
        HapticFeedback.lightImpact();
      }
    });
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Messages'),
        content: Text('Delete ${_selectedMessageIds.length} messages?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _chatService.deleteMessages(_selectedMessageIds.toList());
      setState(() => _selectedMessageIds.clear());
    }
  }

  Future<void> _clearChat() async {
    final roomId = widget.roomId;
    if (roomId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Delete all your messages in this chat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _chatService.clearChat(roomId);
    }
  }

  void _selectAllMessages() {
    setState(() {
      if (_selectedMessageIds.length == _allMessages.length) {
        _selectedMessageIds.clear();
      } else {
        _selectedMessageIds.addAll(_allMessages.map((m) => m.id));
        HapticFeedback.mediumImpact();
      }
    });
  }

  Widget _buildLegacyMessages(String myId) {
    return const Center(
      child: Text(
        'Legacy messages are no longer supported. Please restart this conversation.',
        style: TextStyle(color: AppUi.textMuted, fontSize: 13),
      ),
    );
  }
}
