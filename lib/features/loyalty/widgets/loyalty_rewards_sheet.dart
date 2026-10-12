import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants.dart';
import '../models/loyalty_model.dart';
import '../services/loyalty_service.dart';

class LoyaltyRewardsSheet extends StatefulWidget {
  final String userId;

  const LoyaltyRewardsSheet({super.key, required this.userId});

  static Future<void> show(BuildContext context, String userId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LoyaltyRewardsSheet(userId: userId),
    );
  }

  @override
  State<LoyaltyRewardsSheet> createState() => _LoyaltyRewardsSheetState();
}

class _LoyaltyRewardsSheetState extends State<LoyaltyRewardsSheet>
    with SingleTickerProviderStateMixin {
  final LoyaltyService _service = LoyaltyService();
  final TextEditingController _referralInputController = TextEditingController();

  LoyaltyProfile? _profile;
  List<LoyaltyRewardVoucher> _userVouchers = [];
  List<LoyaltyTransaction> _transactions = [];
  bool _isLoading = true;
  bool _isRedeemingCode = false;
  String? _codeRedemptionMsg;
  bool _showCodeInput = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _referralInputController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final p = await _service.getLoyaltyProfile(widget.userId);
      final v = await _service.getUserVouchers(widget.userId);
      final t = await _service.getTransactions(widget.userId);
      if (mounted) {
        setState(() {
          _profile = p;
          _userVouchers = v;
          _transactions = t;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading loyalty data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _redeemFriendCode() async {
    final code = _referralInputController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isRedeemingCode = true;
      _codeRedemptionMsg = null;
    });

    try {
      await _service.applyReferralCode(
        userId: widget.userId,
        enteredCode: code,
      );
      if (mounted) {
        setState(() {
          _codeRedemptionMsg = 'Successfully applied code! +50 points added!';
          _referralInputController.clear();
          _showCodeInput = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend code applied! +50 bonus points added.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
      await _loadAll();
    } catch (e) {
      if (mounted) {
        setState(() {
          _codeRedemptionMsg = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isRedeemingCode = false);
    }
  }

  Future<void> _redeemVoucher(LoyaltyRewardVoucher template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Redeem Reward'),
        content: Text(
          'Redeem "${template.title}" for ${template.pointsCost} points?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final voucher = await _service.redeemReward(
        userId: widget.userId,
        template: template,
      );
      if (mounted) {
        if (voucher != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Claimed "${voucher.title}"! Apply it at checkout.'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          _tabController.animateTo(1); // switch to My Vouchers tab
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Insufficient loyalty points.')),
          );
        }
      }
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Redemption failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.military_tech_rounded,
                        color: Color(0xFFD97706),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Loyalty Rewards',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Earn points on every refill & referral',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Points Balance Card
                          _buildPointsCard(),
                          const SizedBox(height: 14),
                          // Referral Box
                          _buildReferralCard(),
                          const SizedBox(height: 14),
                          // Tab Bar
                          TabBar(
                            controller: _tabController,
                            labelColor: AppUi.bluePrimary,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: AppUi.bluePrimary,
                            indicatorWeight: 3,
                            tabs: [
                              const Tab(text: 'Redeem Rewards'),
                              Tab(
                                text: 'My Vouchers (${_userVouchers.length})',
                              ),
                              const Tab(text: 'History'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRedeemCatalogTab(),
                    _buildUserVouchersTab(),
                    _buildHistoryTab(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPointsCard() {
    final balance = _profile?.pointsBalance ?? 0;
    final totalEarned = _profile?.totalEarned ?? 0;
    final redeemed = _profile?.totalRedeemed ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'eRefill Points Balance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Member Tier',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$balance',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'pts',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Earned: $totalEarned pts',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                'Used: $redeemed pts',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCard() {
    final refCode = _profile?.referralCode ?? 'EREF-WELCOME';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.people_alt_rounded,
                color: Color(0xFF16A34A),
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Refer Friends & Earn 50 Points Each!',
                  style: TextStyle(
                    color: Color(0xFF15803D),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Share your unique code with family or neighbors. When they enter it, both of you receive +50 points!',
            style: TextStyle(
              color: Color(0xFF166534),
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        refCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 1.5,
                          color: Color(0xFF15803D),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: refCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Referral code copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text:
                        'Join me on eRefill for clean drinking water delivered right to your door! Use my code $refCode to get a free 50 bonus points reward.',
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Referral invite copied! Share with friends.'),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('Share', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_showCodeInput)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _showCodeInput = true),
                child: const Text(
                  'Have a friend\'s referral code? Tap to enter',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _referralInputController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'e.g. EREF-ABC123',
                      hintStyle: const TextStyle(fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF86EFAC)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isRedeemingCode ? null : _redeemFriendCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isRedeemingCode
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Apply'),
                ),
              ],
            ),
            if (_codeRedemptionMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _codeRedemptionMsg!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _codeRedemptionMsg!.contains('Success')
                        ? const Color(0xFF15803D)
                        : Colors.redAccent,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRedeemCatalogTab() {
    final balance = _profile?.pointsBalance ?? 0;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: LoyaltyService.rewardCatalog.length,
      itemBuilder: (context, index) {
        final reward = LoyaltyService.rewardCatalog[index];
        final canAfford = balance >= reward.pointsCost;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: canAfford
                  ? AppUi.bluePrimary.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: canAfford
                      ? AppUi.bluePrimary.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  reward.isDeliveryDiscount
                      ? Icons.local_shipping_rounded
                      : Icons.local_offer_rounded,
                  color: canAfford ? AppUi.bluePrimary : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reward.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.stars_rounded,
                          color: Color(0xFFD97706),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${reward.pointsCost} points',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: canAfford ? () => _redeemVoucher(reward) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppUi.bluePrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.withValues(alpha: 0.2),
                  disabledForegroundColor: Colors.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                child: const Text(
                  'Claim',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserVouchersTab() {
    if (_userVouchers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.confirmation_number_outlined,
              size: 48,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'No active vouchers yet',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Claim a voucher from the "Redeem Rewards" tab!',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _userVouchers.length,
      itemBuilder: (context, index) {
        final v = _userVouchers[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      v.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Ready to Use',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                v.description,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Code: ${v.code}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    'Expires: ${v.expiresAt.month}/${v.expiresAt.day}/${v.expiresAt.year}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    if (_transactions.isEmpty) {
      return const Center(
        child: Text(
          'No loyalty transactions recorded yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        final isPositive = tx.points >= 0;

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: isPositive
                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                : Colors.redAccent.withValues(alpha: 0.1),
            child: Icon(
              isPositive ? Icons.add_rounded : Icons.remove_rounded,
              color: isPositive ? const Color(0xFF10B981) : Colors.redAccent,
              size: 16,
            ),
          ),
          title: Text(
            tx.description,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${tx.createdAt.month}/${tx.createdAt.day}/${tx.createdAt.year} · ${tx.createdAt.hour}:${tx.createdAt.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: Text(
            '${isPositive ? '+' : ''}${tx.points} pts',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isPositive ? const Color(0xFF10B981) : Colors.redAccent,
              fontSize: 13,
            ),
          ),
        );
      },
    );
  }
}
