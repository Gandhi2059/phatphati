// Screen: Seller Dashboard & Vehicle Management Hub
// Allows verified sellers and dealers to list bikes/scooters, create auctions, monitor bidding progress, and track finalized sales.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bid_app/config/supabase_config.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/widgets/countdown_timer_widget.dart';
import 'package:bid_app/widgets/status_badge_widget.dart';
import 'package:bid_app/screens/admin/admin_create_auction_screen.dart';
import 'package:bid_app/screens/buyer/buyer_auction_detail_screen.dart';
import 'package:bid_app/screens/auth/login_screen.dart';

import 'package:bid_app/screens/seller/seller_profile_screen.dart';
import 'package:bid_app/screens/buyer/business_registration_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen>
    with SingleTickerProviderStateMixin {
  final AuctionService _service = AuctionService();
  final NumberFormat _currencyFormatter =
      NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<Auction> _myAuctions = [];
  bool _isLoading = true;
  String _searchQuery = '';

  StreamSubscription<List<Auction>>? _auctionSubscription;
  StreamSubscription<List<Bid>>? _bidSubscription;
  StreamSubscription<Profile>? _profileSubscription;
  StreamSubscription<List<BusinessProfile>>? _businessProfileSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadSellerData();

    _auctionSubscription = _service.auctionStream.listen((_) {
      if (mounted) _loadSellerData();
    });

    _bidSubscription = _service.bidStream.listen((_) {
      if (mounted) _loadSellerData();
    });

    _profileSubscription = _service.profileStream.listen((_) {
      if (mounted) _loadSellerData();
    });

    _businessProfileSubscription = _service.businessProfileStream.listen((_) {
      if (mounted) _loadSellerData();
    });

    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _auctionSubscription?.cancel();
    _bidSubscription?.cancel();
    _profileSubscription?.cancel();
    _businessProfileSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSellerData() async {
    // Refresh user profile from database to get latest business verification status
    try {
      final freshProfile = await _service.fetchUserProfile(_service.currentUser.id);
      if (freshProfile != null) {
        _service.setCurrentProfile(freshProfile);
      }
    } catch (_) {}

    final allAuctions = await _service.fetchAuctions();
    final currentUserId = _service.currentUser.id;
    final user = _service.currentUser;

    // Include auctions created by this seller, created by null/admin, or all platform auctions for sellers/admins
    final sellerAuctions = allAuctions.where((a) {
      return a.createdBy == currentUserId ||
          a.createdBy == null ||
          user.isSeller ||
          user.isAdmin ||
          user.isBusiness;
    }).toList();

    if (mounted) {
      setState(() {
        _myAuctions = sellerAuctions;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCreateAuctionAction() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminCreateAuctionScreen()),
    ).then((_) => _loadSellerData());
  }

  Widget _buildVerificationBanner() {
    final user = _service.currentUser;
    if (user.isAdmin || user.businessStatus == 'approved') {
      return const SizedBox.shrink();
    }

    final isPending = user.businessStatus == 'pending';
    final isRejected = user.businessStatus == 'rejected';

    final Color bgColor = isRejected
        ? AppColors.danger.withValues(alpha: 0.12)
        : (isPending ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7));
    final Color borderColor = isRejected
        ? AppColors.danger.withValues(alpha: 0.4)
        : (isPending ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B));
    final Color textColor = isRejected
        ? AppColors.danger
        : (isPending ? const Color(0xFF0369A1) : const Color(0xFFB45309));
    final IconData icon = isRejected
        ? Icons.cancel_outlined
        : (isPending ? Icons.hourglass_top_rounded : Icons.info_outline_rounded);

    final title = isRejected
        ? 'Business Verification Rejected'
        : (isPending ? 'Verification Pending Admin Approval' : 'Action Required: Complete Form 2');

    final subtitle = isRejected
        ? 'Your registration was rejected. Tap below to review details and resubmit Form 2.'
        : (isPending
            ? 'Form 2 submitted and under Admin review. Auction creation unlocks upon approval.'
            : 'Fill Form 2 (Business Verification) to enable auction creation.');

    final buttonLabel = isRejected ? 'Fix Form 2' : (isPending ? 'View Form 2' : 'Complete Form 2');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                      initialBusinessType: _service.currentUser.accountCategory ?? 'dealer',
                    ),
                  ),
                );
                _loadSellerData();
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

  List<Auction> _filterAuctionsByTab(int tabIndex) {
    List<Auction> filtered = _myAuctions;

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((a) {
        final titleMatch = a.title.toLowerCase().contains(_searchQuery);
        final brandMatch = a.brandName.toLowerCase().contains(_searchQuery);
        final modelMatch = a.model.toLowerCase().contains(_searchQuery);
        return titleMatch || brandMatch || modelMatch;
      }).toList();
    }

    switch (tabIndex) {
      case 1: // Live
        return filtered
            .where((a) => a.activeRound?.status == 'live' || a.status == 'live')
            .toList();
      case 2: // Draft / Scheduled / Upcoming
        return filtered
            .where((a) =>
                a.activeRound?.status == 'upcoming' ||
                a.status == 'draft' ||
                a.status == 'scheduled' ||
                a.status == 'upcoming')
            .toList();
      case 3: // Finalised / Sold
        return filtered
            .where((a) =>
                a.activeRound?.status == 'winner_pending_deposit' ||
                a.activeRound?.status == 'secured' ||
                a.activeRound?.status == 'ended' ||
                a.status == 'secured' ||
                a.status == 'finalised' ||
                a.status == 'ended')
            .toList();
      case 0: // All
      default:
        return filtered;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _service.currentUser;
    final liveCount = _myAuctions.where((a) => a.status == 'live' || a.activeRound?.status == 'live').length;
    final draftCount = _myAuctions.where((a) =>
        a.status == 'draft' ||
        a.status == 'scheduled' ||
        a.status == 'upcoming' ||
        a.activeRound?.status == 'upcoming').length;
    final soldCount = _myAuctions.where((a) =>
        a.status == 'finalised' ||
        a.status == 'secured' ||
        a.status == 'ended' ||
        a.activeRound?.status == 'winner_pending_deposit' ||
        a.activeRound?.status == 'secured' ||
        a.activeRound?.status == 'ended').length;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Seller Dashboard',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${user.fullName} • Dealer Portal',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_rounded, color: Colors.white),
            tooltip: 'My Profile & Account',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SellerProfileScreen()),
              ).then((_) => _loadSellerData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh Listings',
            onPressed: _loadSellerData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: 'All (${_myAuctions.length})'),
            Tab(text: 'Live ($liveCount)'),
            Tab(text: 'Upcoming ($draftCount)'),
            Tab(text: 'Sold ($soldCount)'),
          ],
        ),
      ),
      drawer: Drawer(
        backgroundColor: AppColors.navy,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: AppColors.navy),
              onDetailsPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SellerProfileScreen()),
                ).then((_) => _loadSellerData());
              },
              accountName: Text(
                user.fullName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              accountEmail: Text(user.email),
              currentAccountPicture: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SellerProfileScreen()),
                  ).then((_) => _loadSellerData());
                },
                child: CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Text(
                    user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'S',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_rounded, color: Colors.white),
              title: const Text('My Seller Dashboard', style: TextStyle(color: Colors.white)),
              selected: true,
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.person_rounded, color: Colors.white),
              title: const Text('My Profile & Account', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SellerProfileScreen()),
                ).then((_) => _loadSellerData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
              title: const Text('Create New Auction', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _handleCreateAuctionAction();
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Logout / Switch Account', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                try {
                  await SupabaseConfig.client.auth.signOut();
                } catch (_) {}
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildVerificationBanner(),
          // Seller KPI Summary Header Cards
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.navy,
            child: Row(
              children: [
                Expanded(
                  child: _buildKpiCard(
                    title: 'My Listings',
                    value: '${_myAuctions.length}',
                    icon: Icons.two_wheeler_rounded,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard(
                    title: 'Live Bidding',
                    value: '$liveCount',
                    icon: Icons.gavel_rounded,
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard(
                    title: 'Sold Vehicles',
                    value: '$soldCount',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search my bikes & scooters...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Auction List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAuctionList(_filterAuctionsByTab(0)),
                      _buildAuctionList(_filterAuctionsByTab(1)),
                      _buildAuctionList(_filterAuctionsByTab(2)),
                      _buildAuctionList(_filterAuctionsByTab(3)),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'CREATE AUCTION',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        onPressed: _handleCreateAuctionAction,
      ),
    );
  }

  Future<void> _handleDeleteAuction(Auction auction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text(
              'Delete Auction',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${auction.title}" and all its bids from the database?',
          style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await _service.deleteAuction(auction.id);
      await _loadSellerData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Auction and bids deleted successfully.',
              style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuctionList(List<Auction> auctions) {
    if (auctions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_bike_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No vehicle auctions found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap "+ CREATE AUCTION" to list your first bike or scooter.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: auctions.length,
      itemBuilder: (context, index) {
        final auction = auctions[index];
        final coverImage = auction.images.isNotEmpty ? auction.images.first.imageUrl : null;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BuyerAuctionDetailScreen(auctionId: auction.id),
                ),
              ).then((_) => _loadSellerData());
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vehicle cover & status
                Stack(
                  children: [
                    Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        image: coverImage != null
                            ? DecorationImage(
                                image: NetworkImage(coverImage),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: coverImage == null
                          ? const Center(
                              child: Icon(Icons.two_wheeler_rounded, size: 48, color: Colors.grey),
                            )
                          : null,
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: StatusBadgeWidget(status: auction.effectiveStatus),
                    ),
                    if (auction.isLive)
                      Positioned(
                        bottom: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: CountdownTimerWidget(
                            key: ValueKey('seller_timer_${auction.id}_${auction.activeRound?.id}'),
                            targetTime: auction.endTime,
                            compact: true,
                            onTimerExpired: () => _loadSellerData(),
                          ),
                        ),
                      ),
                  ],
                ),

                // Details & Price
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  auction.title,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.navy,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${auction.registrationNumber} • Lot: ${auction.lotNumber}',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 22),
                            tooltip: 'Delete Auction & Bids',
                            onPressed: () => _handleDeleteAuction(auction),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'STARTING PRICE',
                                  style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppColors.secondaryText, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currencyFormatter.format(auction.startingPrice),
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.navy),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'CURRENT HIGHEST',
                                  style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currencyFormatter.format(auction.currentPrice),
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.gavel_rounded, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${auction.bidCount} Bids Received',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const Spacer(),
                          const Text(
                            'View Details →',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),

                      // SOLD / RESERVED Banner for Seller
                      Builder(
                        builder: (_) {
                          final isSold = auction.activeRound?.status == 'winner_pending_deposit' ||
                              auction.activeRound?.status == 'secured' ||
                              auction.status == 'secured' ||
                              auction.status == 'finalised' ||
                              (auction.status == 'ended' && auction.currentPrice > 0);

                          if (!isSold) return const SizedBox.shrink();

                          final isVerified = auction.activeRound?.status == 'secured' || auction.status == 'secured';

                          return Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '🎉 VEHICLE SOLD: ${_currencyFormatter.format(auction.currentPrice)}',
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.success,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isVerified
                                            ? '10% Deposit Verified • Vehicle Reserved'
                                            : 'Winning Bid Accepted • Awaiting Deposit Verification',
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.navy,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _showSoldBookingDetails(auction),
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  child: const Text('INFO', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdminCreateAuctionScreen(auction: auction),
                                  ),
                                );
                                _loadSellerData();
                              },
                              icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.navy),
                              label: const Text('EDIT AUCTION', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _handleDeleteAuction(auction),
                              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                              label: const Text('DELETE', style: TextStyle(fontFamily: 'Inter', color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.danger),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
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
    );
  }

  Future<void> _showSoldBookingDetails(Auction auction) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return FutureBuilder<DepositRecord?>(
          future: _service.fetchDepositRecordForAuction(auction.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              );
            }

            final record = snapshot.data;
            final isVerified = record?.status == 'verified';
            final winningAmount = (record != null && record.winningAmount > 0) ? record.winningAmount : auction.currentPrice;
            final depositAmount = (record != null && record.depositAmount > 0) ? record.depositAmount : (winningAmount * 0.10);
            final remainingBalance = (record != null && record.remainingBalance > 0) ? record.remainingBalance : (winningAmount - depositAmount);

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('VEHICLE SOLD / RESERVED', style: TextStyle(fontFamily: 'Inter', color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(auction.title, style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.navy),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.border),
                    // Status Badge
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isVerified ? AppColors.success.withValues(alpha: 0.1) : AppColors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isVerified ? AppColors.success : AppColors.amber),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isVerified ? Icons.verified_user_rounded : Icons.pending_actions_rounded,
                            color: isVerified ? AppColors.success : AppColors.amber,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isVerified
                                  ? '10% Booking Deposit Verified • Vehicle Officially Reserved'
                                  : 'Winning Bid Accepted • 10% Deposit Awaiting Admin Verification',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: isVerified ? AppColors.success : AppColors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Price Breakdown
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _buildSoldDetailRow('Final Selling Price', _currencyFormatter.format(winningAmount), isBold: true, color: AppColors.primary),
                          const SizedBox(height: 8),
                          _buildSoldDetailRow('10% Security Deposit', _currencyFormatter.format(depositAmount), isBold: false),
                          const SizedBox(height: 8),
                          _buildSoldDetailRow('90% Balance Due upon Bluebook Transfer', _currencyFormatter.format(remainingBalance), isBold: true),
                          if (record?.bookingReference != null && record!.bookingReference.isNotEmpty) ...[
                            const Divider(height: 16, color: AppColors.border),
                            _buildSoldDetailRow('Booking Reference', record.bookingReference, isBold: true, color: AppColors.navy),
                          ],
                        ],
                      ),
                    ),
                    if (record?.winnerProfile != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Buyer Information', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            Text('Name: ${record!.winnerProfile!.fullName}', style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 12)),
                            if (record.winnerProfile!.phone != null)
                              Text('Contact: ${record.winnerProfile!.phone}', style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 12)),
                            if (record.winnerProfile!.buyerId != null)
                              Text('Buyer ID: ${record.winnerProfile!.buyerId}', style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                    if (record?.nextStepInstructions != null && record!.nextStepInstructions!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: AppColors.success, size: 16),
                                SizedBox(width: 6),
                                Text('Admin Handover Instructions', style: TextStyle(fontFamily: 'Inter', color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(record.nextStepInstructions!, style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 12, height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSoldDetailRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12, fontWeight: isBold ? FontWeight.w600 : FontWeight.normal)),
        Text(value, style: TextStyle(fontFamily: 'Inter', color: color ?? AppColors.navy, fontSize: isBold ? 13 : 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}
