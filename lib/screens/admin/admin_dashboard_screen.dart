// Screen: Admin Live Auction Monitoring Dashboard & Management Hub
// Identical rich visual vehicle card layout and sidebar structure as Buyer Dashboard with full Admin management controls.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bid_app/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/widgets/countdown_timer_widget.dart';
import 'package:bid_app/widgets/status_badge_widget.dart';
import 'package:bid_app/screens/admin/admin_create_auction_screen.dart';
import 'package:bid_app/screens/admin/admin_buyer_management_screen.dart';
import 'package:bid_app/screens/admin/admin_audit_log_screen.dart';
import 'package:bid_app/screens/admin/admin_business_review_screen.dart';
import 'package:bid_app/screens/admin/admin_deposit_verification_screen.dart';
import 'package:bid_app/screens/buyer/buyer_auction_detail_screen.dart';
import 'package:bid_app/screens/notifications/notification_center_screen.dart';
import 'package:bid_app/screens/auth/login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final AuctionService _service = AuctionService();
  final NumberFormat _currencyFormatter =
      NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<Auction> _auctions = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int _pendingBusinessCount = 0;
  int _pendingDepositCount = 0;
  int _pendingForm1Count = 0;
  int _unreadNotificationCount = 0;

  StreamSubscription<List<Auction>>? _auctionSubscription;
  StreamSubscription<List<Bid>>? _bidSubscription;
  StreamSubscription<List<NotificationModel>>? _notifSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadDashboardData();

    _auctionSubscription = _service.auctionStream.listen((_) {
      if (mounted) _loadDashboardData();
    });

    _bidSubscription = _service.bidStream.listen((_) {
      if (mounted) _loadDashboardData();
    });

    _notifSubscription = _service.notificationStream.listen((_) {
      if (mounted) _loadDashboardData();
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
    _notifSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    final list = await _service.fetchAuctions();
    final pendingBiz = await _service.fetchPendingBusinessProfiles();
    final deposits = await _service.fetchAllDepositRecordsForAdmin();
    final allUsers = await _service.fetchRegisteredUsers();
    final unreadCount = await _service.getUnreadNotificationCount();

    final pendingDep = deposits
        .where((d) =>
            d.status == 'submitted_for_verification' ||
            d.status == 'pending_deposit')
        .length;

    final pendingF1 = allUsers
        .where((u) =>
            u.businessProfileId == null ||
            u.businessStatus == null ||
            u.businessStatus == 'none')
        .length;

    if (mounted) {
      setState(() {
        _auctions = list;
        _pendingBusinessCount =
            pendingBiz.where((b) => b.status == 'pending').length;
        _pendingDepositCount = pendingDep;
        _pendingForm1Count = pendingF1;
        _unreadNotificationCount = unreadCount;
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerServerCronProcess() async {
    await _service.processStateTransitions();
    await _loadDashboardData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Server transition engine executed. States refreshed.',
            style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.navy,
        ),
      );
    }
  }

  Future<void> _handlePurgeAllBids() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text(
              'Purge All Bids',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete ALL placed bids and reset auction highest bid amounts to zero? This action cannot be undone.',
          style: TextStyle(
              fontFamily: 'Inter',
              color: AppColors.secondaryText,
              fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('PURGE ALL BIDS',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await _service.purgeAllBids();
      await _loadDashboardData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'All bids deleted and auction round amounts reset.',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
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
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${auction.title}" and all its bids from the database?',
          style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.secondaryText,
              fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await _service.deleteAuction(auction.id);
      await _loadDashboardData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Auction and bids deleted successfully.',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _handleRepeatWinnerDecision(Auction auction) async {
    String selectedDecision = 'approve';
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'REPEAT WINNER REVIEW',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.navy,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      '⚠️ WARNING: The winner of this re-auction previously defaulted on a deposit payment for the parent vehicle auction.\n\nAuction: ${auction.title}\nWinning Bid: Rs. ${auction.activeRound?.currentHighestBid.toStringAsFixed(0) ?? auction.startingPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.orange.shade900,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Admin Action:',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  RadioListTile<String>(
                    value: 'approve',
                    groupValue: selectedDecision,
                    title: const Text('Approve & Request Deposit',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.navy)),
                    onChanged: (val) =>
                        setDialogState(() => selectedDecision = val!),
                  ),
                  RadioListTile<String>(
                    value: 'reject_winner',
                    groupValue: selectedDecision,
                    title: const Text('Reject Winning Bid',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.navy)),
                    onChanged: (val) =>
                        setDialogState(() => selectedDecision = val!),
                  ),
                  RadioListTile<String>(
                    value: 're_auction',
                    groupValue: selectedDecision,
                    title: const Text('Trigger Immediate Re-Auction',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.navy)),
                    onChanged: (val) =>
                        setDialogState(() => selectedDecision = val!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.navy,
                        fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Mandatory Admin Reason *',
                      labelStyle: const TextStyle(
                          fontFamily: 'Inter', color: AppColors.secondaryText),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.secondaryText,
                        fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('SUBMIT DECISION',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && reasonController.text.trim().isNotEmpty) {
      setState(() => _isLoading = true);
      await _service.resolveRepeatWinnerAuction(
        auctionId: auction.id,
        decision: selectedDecision,
        adminReason: reasonController.text.trim(),
      );
      await _loadDashboardData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Admin decision ($selectedDecision) submitted.'),
              backgroundColor: AppColors.success),
        );
      }
    }
  }

  List<Auction> _filterAuctions(List<Auction> source) {
    if (_searchQuery.isEmpty) return source;
    return source.where((a) {
      final title = a.title.toLowerCase();
      final brand = a.brandName.toLowerCase();
      final model = a.model.toLowerCase();
      final lot = a.lotNumber.toLowerCase();
      final reg = a.registrationNumber.toLowerCase();
      return title.contains(_searchQuery) ||
          brand.contains(_searchQuery) ||
          model.contains(_searchQuery) ||
          lot.contains(_searchQuery) ||
          reg.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = _service.currentUser;

    final allFiltered = _filterAuctions(_auctions);
    final liveAuctions =
        _filterAuctions(_auctions.where((a) => a.isLive).toList());
    final upcomingAuctions =
        _filterAuctions(_auctions.where((a) => a.isUpcoming).toList());
    final depositPendingAuctions = _filterAuctions(_auctions
        .where((a) => a.effectiveStatus == 'winner_pending_deposit')
        .toList());
    final closedAuctions =
        _filterAuctions(_auctions.where((a) => a.isCompleted).toList());

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _buildAdminSidebar(context, user),
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.menu_outlined, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Admin Dashboard',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Live Auction & Bids Hub',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Color(0xFFDDE2E5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _unreadNotificationCount > 0,
              label: Text('$_unreadNotificationCount'),
              child:
                  const Icon(Icons.notifications_outlined, color: Colors.white),
            ),
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationCenterScreen()),
              );
              _loadDashboardData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
            tooltip: 'Purge All Bids',
            onPressed: _handlePurgeAllBids,
          ),
          IconButton(
            icon: const Icon(Icons.sync_outlined, color: Colors.white),
            tooltip: 'Run Server State Engine',
            onPressed: _triggerServerCronProcess,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: Colors.white),
            tooltip: 'Create New Vehicle Auction',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminCreateAuctionScreen()),
              );
              _loadDashboardData();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Create Auction',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminCreateAuctionScreen()),
          );
          _loadDashboardData();
        },
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                // Top Search Bar
                Container(
                  color: AppColors.card,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.navy,
                        fontSize: 14),
                    decoration: InputDecoration(
                      hintText:
                          'Search by title, brand, model, lot or reg no...',
                      hintStyle: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.secondaryText,
                          fontSize: 13),
                      prefixIcon: const Icon(Icons.search_outlined,
                          color: AppColors.secondaryText, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: AppColors.secondaryText, size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),

                // Category & Status Filter Tabs
                Container(
                  color: AppColors.card,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: AppColors.primary,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.secondaryText,
                    labelStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                    tabs: [
                      Tab(text: 'ALL (${allFiltered.length})'),
                      Tab(text: 'LIVE (${liveAuctions.length})'),
                      Tab(text: 'UPCOMING (${upcomingAuctions.length})'),
                      Tab(text: 'DEPOSIT (${depositPendingAuctions.length})'),
                      Tab(text: 'CLOSED (${closedAuctions.length})'),
                    ],
                  ),
                ),

                // Vehicle Grid / List Body
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAuctionList(allFiltered),
                      _buildAuctionList(liveAuctions),
                      _buildAuctionList(upcomingAuctions),
                      _buildAuctionList(depositPendingAuctions),
                      _buildAuctionList(closedAuctions),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAdminSidebar(BuildContext context, Profile user) {
    return Drawer(
      backgroundColor: AppColors.card,
      child: Column(
        children: [
          // Admin Profile Header Card
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
                      child: const Icon(Icons.admin_panel_settings_outlined,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            user.email,
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                color: Color(0xFFDDE2E5),
                                fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ADMINISTRATOR',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Admin Sidebar Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _buildSidebarItem(
                  icon: Icons.dashboard_outlined,
                  title: 'Admin Dashboard',
                  iconColor: AppColors.navy,
                  onTap: () => Navigator.pop(context),
                ),
                _buildSidebarItem(
                  icon: Icons.store_outlined,
                  title: 'Business Registrations',
                  iconColor: AppColors.navy,
                  badgeCount: _pendingBusinessCount,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const AdminBusinessReviewScreen()))
                        .then((_) => _loadDashboardData());
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.verified_user_outlined,
                  title: 'Deposit Verification',
                  iconColor: AppColors.navy,
                  badgeCount: _pendingDepositCount,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const AdminDepositVerificationScreen()))
                        .then((_) => _loadDashboardData());
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.history_outlined,
                  title: 'System Audit Logs',
                  iconColor: AppColors.navy,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AdminAuditLogScreen()));
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.manage_accounts_outlined,
                  title: 'User Accounts & Form 1 Review',
                  iconColor: AppColors.navy,
                  badgeCount: _pendingForm1Count,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const AdminBuyerManagementScreen()))
                        .then((_) => _loadDashboardData());
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.add_circle_outline_rounded,
                  title: 'Create Vehicle Auction',
                  iconColor: AppColors.navy,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const AdminCreateAuctionScreen()))
                        .then((_) => _loadDashboardData());
                  },
                ),
                const Divider(color: AppColors.border),
                _buildSidebarItem(
                  icon: Icons.sync_outlined,
                  title: 'Sync Server State Engine',
                  iconColor: AppColors.navy,
                  onTap: () {
                    Navigator.pop(context);
                    _triggerServerCronProcess();
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.key_outlined,
                  title: 'Change Admin Password',
                  iconColor: AppColors.navy,
                  onTap: () {
                    Navigator.pop(context);
                    _showChangePasswordDialog();
                  },
                ),
              ],
            ),
          ),

          const Divider(color: AppColors.border, height: 1),
          ListTile(
            leading: const Icon(Icons.logout_outlined, color: AppColors.danger),
            title: const Text('Sign Out',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600)),
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

  Future<void> _showChangePasswordDialog() async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Change Admin Password',
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account: ${AuctionService().currentUser.email}',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: obscure,
                  style: const TextStyle(
                      fontFamily: 'Inter', color: AppColors.navy),
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border)),
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Password must be at least 6 characters'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: obscure,
                  style: const TextStyle(
                      fontFamily: 'Inter', color: AppColors.navy),
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  validator: (v) => v != newPasswordController.text
                      ? 'Passwords do not match'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'Inter', color: AppColors.secondaryText)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final newPass = newPasswordController.text.trim();
                Navigator.pop(ctx);
                try {
                  await SupabaseConfig.client.auth.updateUser(
                    UserAttributes(password: newPass),
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Admin password updated successfully!',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update password: $e',
                          style: const TextStyle(
                              fontFamily: 'Inter', color: Colors.white)),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              },
              child: const Text('Update Password',
                  style: TextStyle(
                      fontFamily: 'Inter', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
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
      title: Text(title,
          style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.navy,
              fontWeight: FontWeight.w500,
              fontSize: 14)),
      trailing: badgeCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$badgeCount',
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            )
          : null,
      onTap: onTap,
    );
  }

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'winner_pending_deposit':
        return 'Deposit Due';
      case 'manual_review_required':
        return 'Review Req.';
      case 'active':
        return 'Active';
      case 'extended':
        return 'Extended';
      case 'upcoming':
        return 'Upcoming';
      case 'secured':
      case 'deposit_verified':
      case 'verified':
        return 'Secured';
      case 'completed':
        return 'Completed';
      case 'unsold':
        return 'Unsold';
      case 'failed':
        return 'Failed';
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  Widget _buildAuctionList(List<Auction> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'No vehicle auctions found in this view.',
          style: TextStyle(
              fontFamily: 'Inter',
              color: AppColors.secondaryText,
              fontSize: 14),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
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

          return Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
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
                // Vehicle Photo Thumbnail Header
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
                        ),
                      ),
                      if (a.isBusinessAuction)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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

                // Vehicle Details & Metrics Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              a.title,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.navy,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_note_outlined,
                                    color: AppColors.primary, size: 24),
                                tooltip: 'Edit Vehicle Auction',
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AdminCreateAuctionScreen(auction: a),
                                    ),
                                  );
                                  _loadDashboardData();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: AppColors.danger, size: 22),
                                tooltip: 'Delete Auction & Bids',
                                onPressed: () => _handleDeleteAuction(a),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        '${a.brandName} ${a.model} (${a.builtYear}) • Lot: ${a.lotNumber}',
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.secondaryText,
                            fontSize: 12),
                      ),
                      const SizedBox(height: 8),

                      if (r != null)
                        CountdownTimerWidget(
                          key: ValueKey(
                              'admin_timer_${a.id}_${r.id}_${isUpcoming ? "up" : "live"}'),
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
                          onTimerExpired: () => _loadDashboardData(),
                        ),
                      const SizedBox(height: 12),

                      // Metrics Summary
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'HIGHEST BID',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.secondaryText,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _currencyFormatter.format(
                                          r?.currentHighestBid ??
                                              a.startingPrice),
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.primary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ROUND STATUS',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.secondaryText,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _formatStatus(r?.status ?? a.status),
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.navy,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'LEADING BUYER',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.secondaryText,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      r?.highestBidderId != null
                                          ? 'Buyer Active'
                                          : 'No Bids',
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.navy,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Admin Repeat Winner Manual Review Card
                      if (r?.status == 'manual_review_required' ||
                          a.requiresManualReview) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.orange.shade400, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Colors.orange, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    '🚨 REPEAT WINNER MANUAL REVIEW REQUIRED',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: Colors.orange,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                a.manualReviewReason ??
                                    'Winning buyer previously defaulted on deposit payment for parent vehicle auction.',
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: Colors.orange.shade900,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade800,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon:
                                      const Icon(Icons.gavel_rounded, size: 16),
                                  label: const Text(
                                    'REVIEW REPEAT WINNER & TAKE ACTION',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                  onPressed: () =>
                                      _handleRepeatWinnerDecision(a),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Admin Deposit Tracker Card
                      if (isDepositPending) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.amber.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.payment_outlined,
                                      color: AppColors.amber, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    '10% WINNER BOOKING DEPOSIT TRACKER',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.amber,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Winning Amount: ${_currencyFormatter.format(r?.winningBid ?? r?.currentHighestBid ?? 0)} | 10% Deposit: ${_currencyFormatter.format(r?.depositRequired ?? ((r?.currentHighestBid ?? 0) * 0.10))}',
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.navy,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Deadline: ${ServerTimeService.formatNepal(r?.depositDeadline ?? DateTime.now(), pattern: 'hh:mm a, MMM d')}',
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.amber,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const AdminDepositVerificationScreen()),
                                      ).then((_) => _loadDashboardData());
                                    },
                                    child: const Text('Verify Deposit >',
                                        style: TextStyle(
                                            fontFamily: 'Inter',
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Action Buttons Bar
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AdminCreateAuctionScreen(auction: a),
                                  ),
                                );
                                _loadDashboardData();
                              },
                              icon: const Icon(Icons.edit_outlined,
                                  size: 15, color: AppColors.navy),
                              label: const Text('EDIT',
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.border),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _handleDeleteAuction(a),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 15, color: AppColors.danger),
                              label: const Text('DELETE',
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.danger),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BuyerAuctionDetailScreen(
                                        auctionId: a.id),
                                  ),
                                );
                                _loadDashboardData();
                              },
                              icon: const Icon(Icons.gavel_outlined,
                                  size: 15, color: Colors.white),
                              label: const Text('VIEW',
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
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
          );
        },
      ),
    );
  }
}
