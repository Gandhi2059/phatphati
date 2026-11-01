// Screen: Buyer Home Dashboard & Auction Discovery
// Features a clean side navigation drawer (Sidebar) replacing top actions clutter.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bid_app/config/supabase_config.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/widgets/countdown_timer_widget.dart';
import 'package:bid_app/widgets/status_badge_widget.dart';
import 'package:bid_app/screens/buyer/buyer_auction_detail_screen.dart';
import 'package:bid_app/screens/buyer/my_bids_screen.dart';
import 'package:bid_app/screens/buyer/won_auctions_screen.dart';
import 'package:bid_app/screens/buyer/my_business_screen.dart';
import 'package:bid_app/screens/buyer/business_registration_screen.dart';
import 'package:bid_app/screens/admin/admin_dashboard_screen.dart';
import 'package:bid_app/screens/notifications/notification_center_screen.dart';
import 'package:bid_app/screens/auth/login_screen.dart';

class BuyerHomeScreen extends StatefulWidget {
  const BuyerHomeScreen({super.key});

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen>
    with SingleTickerProviderStateMixin {
  final AuctionService _service = AuctionService();

  final NumberFormat _currencyFormatter =
      NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomNavIndex = 0;
  late TabController _tabController;
  List<Auction> _auctions = [];
  bool _isLoading = true;
  int _unreadCount = 0;

  StreamSubscription<List<NotificationModel>>? _notifSubscription;
  StreamSubscription<List<Auction>>? _auctionSubscription;
  StreamSubscription<Profile>? _profileSubscription;
  StreamSubscription<List<BusinessProfile>>? _businessProfileSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();

    _notifSubscription = _service.notificationStream.listen((_) async {
      final unread = await _service.getUnreadNotificationCount();
      if (mounted) {
        setState(() {
          _unreadCount = unread;
        });
      }
    });

    _auctionSubscription = _service.auctionStream.listen((auctions) {
      if (mounted) {
        setState(() {
          _auctions = auctions;
        });
      }
    });

    _profileSubscription = _service.profileStream.listen((_) {
      if (mounted) _loadData();
    });

    _businessProfileSubscription = _service.businessProfileStream.listen((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notifSubscription?.cancel();
    _auctionSubscription?.cancel();
    _profileSubscription?.cancel();
    _businessProfileSubscription?.cancel();
    super.dispose();
  }

  List<Bid> _myBids = [];

  Future<void> _loadData() async {
    try {
      final fresh = await _service.fetchUserProfile(_service.currentUser.id);
      if (fresh != null) _service.setCurrentProfile(fresh);
    } catch (_) {}

    final list = await _service.fetchAuctions();
    final unread = await _service.getUnreadNotificationCount();
    final myBids = await _service.fetchBuyerBids(_service.currentUser.id);
    if (mounted) {
      setState(() {
        _auctions = list;
        _unreadCount = unread;
        _myBids = myBids;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    await SupabaseConfig.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _service.currentUser;
    final myBiddedAuctionIds = _myBids.map((b) => b.auctionId).toSet();

    final liveAuctions = _auctions.where((a) => a.isLive).toList();

    final upcomingAuctions = _auctions.where((a) => a.isUpcoming).toList();

    // Ended / Completed auctions are ONLY shown if the buyer has placed a bid on it
    final completedAuctions = _auctions.where((a) {
      final isEnded = a.isCompleted || a.effectiveStatus == 'winner_pending_deposit';
      final hasBidded = myBiddedAuctionIds.contains(a.id) ||
          a.activeRound?.highestBidderId == user.id;
      return isEnded && hasBidded;
    }).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _buildBuyerSidebar(context, user),
      appBar: _bottomNavIndex == 0
          ? AppBar(
              backgroundColor: AppColors.navy,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.menu_outlined, color: Colors.white),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PHATPHATI AUCTIONS',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.0,
                      ),
                    ),
                    if (user.buyerId != null)
                      Text(
                        'ID: ${user.buyerId} | ${user.fullName}',
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Color(0xFFDDE2E5),
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ),
              actions: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationCenterScreen()));
                        _loadData();
                      },
                    ),
                    if (_unreadCount > 0)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$_unreadCount',
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : IndexedStack(
              index: _bottomNavIndex,
              children: [
                _buildAuctionsDiscoveryBody(
                    liveAuctions, upcomingAuctions, completedAuctions),
                const MyBidsScreen(),
                const WonAuctionsScreen(),
              ],
            ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _bottomNavIndex,
          onTap: (index) {
            if (index == 3) {
              _scaffoldKey.currentState?.openDrawer();
            } else {
              setState(() {
                _bottomNavIndex = index;
              });
            }
          },
          backgroundColor: AppColors.card,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.secondaryText,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          selectedLabelStyle:
              const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 11),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.gavel_outlined),
              label: 'Auctions',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              label: 'My Bids',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events_outlined),
              label: 'Won',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  const Icon(Icons.menu_outlined),
                  if (_unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Sidebar',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuyerVerificationBanner() {
    final user = _service.currentUser;
    if (user.isAdmin || user.businessStatus == 'approved') {
      return const SizedBox.shrink();
    }

    final isPending = user.businessStatus == 'pending';
    final isRejected = user.businessStatus == 'rejected';

    final Color bgColor = isRejected
        ? AppColors.danger.withValues(alpha: 0.1)
        : (isPending ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7));
    final Color borderColor = isRejected
        ? AppColors.danger.withValues(alpha: 0.3)
        : (isPending ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B));
    final Color textColor = isRejected
        ? AppColors.danger
        : (isPending ? const Color(0xFF0369A1) : const Color(0xFFB45309));
    final IconData icon = isRejected
        ? Icons.cancel_outlined
        : (isPending ? Icons.hourglass_top_rounded : Icons.info_outline_rounded);

    final title = isRejected
        ? 'Business Verification Rejected'
        : (isPending ? 'Verification Pending Admin Review' : 'Form 2 Business Verification Required');

    final subtitle = isRejected
        ? 'Admin rejected your documentation. Tap to review notes and update Form 2.'
        : (isPending
            ? 'Your verification is under review. Bidding unlocks once approved by Admin.'
            : 'Submit Form 2 (Business Verification & Docs) to unlock live bidding.');

    final buttonLabel = isRejected ? 'Fix Form 2' : (isPending ? 'View Form 2' : 'Complete Form 2');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Inter',
              color: textColor.withValues(alpha: 0.9),
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                final biz = await _service.fetchCurrentUserBusinessProfile();
                if (!mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BusinessRegistrationScreen(
                      existingProfile: biz,
                      initialBusinessType: _service.currentUser.accountCategory ?? 'recondition',
                    ),
                  ),
                );
                _loadData();
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 14),
              label: Text(buttonLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: textColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuctionsDiscoveryBody(
      List<Auction> liveAuctions,
      List<Auction> upcomingAuctions,
      List<Auction> completedAuctions) {
    return Column(
      children: [
        _buildBuyerVerificationBanner(),
        Container(
          color: AppColors.card,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.secondaryText,
            labelStyle:
                const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              Tab(text: 'LIVE (${liveAuctions.length})'),
              Tab(text: 'UPCOMING (${upcomingAuctions.length})'),
              Tab(text: 'WON (${completedAuctions.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAuctionList(liveAuctions),
              _buildAuctionList(upcomingAuctions),
              _buildAuctionList(completedAuctions),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBuyerSidebar(BuildContext context, Profile user) {
    final businessStatus = user.businessStatus ?? 'none';

    return Drawer(
      backgroundColor: AppColors.card,
      child: Column(
        children: [
          // User Header Card
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            color: AppColors.navy,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      child: const Icon(Icons.person_outline, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            user.email,
                            style: const TextStyle(fontFamily: 'Inter', color: Color(0xFFDDE2E5), fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (user.buyerId != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                user.buyerId!,
                                style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: businessStatus == 'approved'
                        ? AppColors.success.withValues(alpha: 0.15)
                        : (businessStatus == 'rejected'
                            ? AppColors.danger.withValues(alpha: 0.15)
                            : AppColors.warning.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        businessStatus == 'approved'
                            ? Icons.verified_outlined
                            : (businessStatus == 'rejected'
                                ? Icons.cancel_outlined
                                : Icons.hourglass_empty_outlined),
                        color: businessStatus == 'approved'
                            ? AppColors.success
                            : (businessStatus == 'rejected'
                                ? AppColors.danger
                                : AppColors.warning),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        businessStatus == 'approved'
                            ? 'VERIFIED BUYER'
                            : (businessStatus == 'rejected'
                                ? 'VERIFICATION REJECTED'
                                : (businessStatus == 'pending'
                                    ? 'VERIFICATION PENDING'
                                    : 'FORM 2 REQUIRED')),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: businessStatus == 'approved'
                              ? AppColors.success
                              : (businessStatus == 'rejected'
                                  ? AppColors.danger
                                  : AppColors.warning),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),


          // Menu ListItems
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _buildSidebarItem(
                  icon: Icons.storefront_outlined,
                  title: 'Auctions Discovery',
                  iconColor: AppColors.navy,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _bottomNavIndex = 0;
                    });
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.gavel_outlined,
                  title: 'My Bids',
                  iconColor: AppColors.navy,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _bottomNavIndex = 1;
                    });
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.emoji_events_outlined,
                  title: 'Won Auctions & Deposits',
                  iconColor: AppColors.navy,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _bottomNavIndex = 2;
                    });
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.business_center_outlined,
                  title: 'My Business Profile',
                  iconColor: AppColors.navy,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBusinessScreen()));
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  badgeCount: _unreadCount,
                  iconColor: AppColors.navy,
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen()));
                    _loadData();
                  },
                ),
                if (user.isAdmin) ...[
                  const Divider(color: AppColors.border),
                  _buildSidebarItem(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Admin Dashboard',
                    iconColor: AppColors.danger,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                    },
                  ),
                ],
              ],
            ),
          ),

          const Divider(color: AppColors.border, height: 1),
          // Logout Option
          ListTile(
            leading: const Icon(Icons.logout_outlined, color: AppColors.danger),
            title: const Text('Sign Out', style: TextStyle(fontFamily: 'Inter', color: AppColors.danger, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _handleLogout();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String title,
    required Color iconColor,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w500, fontSize: 14)),
      trailing: badgeCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(10)),
              child: Text('$badgeCount', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _buildAuctionList(List<Auction> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'No auctions in this section.',
          style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 14),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final a = list[index];
          final r = a.activeRound;
          final effectiveStatus = r?.effectiveStatus ?? a.effectiveStatus;
          final isUpcoming = effectiveStatus == 'upcoming';
          final isDepositPending = effectiveStatus == 'winner_pending_deposit';
          final isLeading = r?.highestBidderId == _service.currentUser.id;

          return InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BuyerAuctionDetailScreen(auctionId: a.id)),
              );
              _loadData();
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isLeading
                      ? AppColors.success
                      : AppColors.border,
                  width: isLeading ? 1.5 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(10)),
                    child: Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            a.primaryImageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.background,
                              child: const Icon(Icons.two_wheeler_outlined,
                                  color: AppColors.secondaryText, size: 48),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: StatusBadgeWidget(
                            status: effectiveStatus,
                            isLeading: isLeading,
                          ),
                        ),
                        if (a.isBusinessAuction)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.navy,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Verified Seller',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (r != null)
                          CountdownTimerWidget(
                            key: ValueKey('timer_${a.id}_${r.id}_${isUpcoming ? "up" : "live"}'),
                            targetTime: isUpcoming
                                ? r.startAt
                                : (isDepositPending
                                    ? (r.depositDeadline ?? DateTime.now())
                                    : r.endAt),
                            mode: isUpcoming
                                ? TimerMode.startsIn
                                : (isDepositPending
                                    ? TimerMode.depositDeadline
                                    : TimerMode.endsIn),
                            compact: true,
                            onTimerExpired: () => _loadData(),
                          ),
                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CURRENT BID',
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.secondaryText,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  _currencyFormatter.format(
                                      r?.currentHighestBid ?? a.startingPrice),
                                  style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.primary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => BuyerAuctionDetailScreen(
                                          auctionId: a.id)),
                                );
                                _loadData();
                              },
                              icon: const Icon(Icons.gavel_rounded, size: 16),
                              label: const Text(
                                'BID NOW',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                elevation: 1,
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
          );
        },
      ),
    );
  }
}

