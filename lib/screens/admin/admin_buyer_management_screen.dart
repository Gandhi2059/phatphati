// Screen: Admin User Management & Form 1 Registration Review
// Allows Admins to inspect all registered Buyer & Seller accounts, review Form 1 submissions,
// and delete unlegit accounts before or during the second filling (Business Details).

import 'package:flutter/material.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/utils/nepal_phone_helper.dart';

class AdminBuyerManagementScreen extends StatefulWidget {
  const AdminBuyerManagementScreen({super.key});

  @override
  State<AdminBuyerManagementScreen> createState() =>
      _AdminBuyerManagementScreenState();
}

class _AdminBuyerManagementScreenState
    extends State<AdminBuyerManagementScreen> {
  final AuctionService _service = AuctionService();
  final _createFormKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();

  List<Profile> _allUsers = [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _deletingUserId;
  String _selectedFilter = 'all'; // 'all', 'pending_form2', 'buyer', 'seller'
  String _searchQuery = '';
  bool _showCreateForm = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
        });
      }
    });
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final users = await _service.fetchRegisteredUsers();
    if (mounted) {
      setState(() {
        _allUsers = users;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Profile> get _filteredUsers {
    return _allUsers.where((u) {
      // Role & status filter
      if (_selectedFilter == 'pending_form2') {
        final isPending = u.businessProfileId == null ||
            u.businessStatus == null ||
            u.businessStatus == 'none';
        if (!isPending) return false;
      } else if (_selectedFilter == 'buyer') {
        if (!u.isBuyer) return false;
      } else if (_selectedFilter == 'seller') {
        if (!u.isSeller) return false;
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final nameMatch = u.fullName.toLowerCase().contains(_searchQuery);
        final emailMatch = u.email.toLowerCase().contains(_searchQuery);
        final phoneMatch = (u.phone ?? '').toLowerCase().contains(_searchQuery);
        final buyerIdMatch =
            (u.buyerId ?? '').toLowerCase().contains(_searchQuery);
        return nameMatch || emailMatch || phoneMatch || buyerIdMatch;
      }

      return true;
    }).toList();
  }

  Future<void> _handleDeleteUser(Profile user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.person_remove_rounded,
                color: AppColors.danger, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Unlegit User?',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to permanently delete this user account?\n',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.secondaryText,
                  fontSize: 13),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Email: ${user.email}',
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.secondaryText,
                        fontSize: 12),
                  ),
                  if (user.phone != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Phone: ${NepalPhoneHelper.formatDisplay(user.phone!)}',
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.secondaryText,
                          fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Role: ${user.isSeller ? 'Seller (Dealer)' : 'Buyer (Reconditioner)'}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      color:
                          user.isSeller ? AppColors.amber : AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will completely remove their credentials from Supabase Auth and User Profiles before they complete the second registration form.',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.danger,
                  fontSize: 11,
                  fontWeight: FontWeight.w500),
            ),
          ],
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
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE UNLEGIT USER',
                style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deletingUserId = user.id);

    try {
      await _service.deleteUserProfile(user.id);
      await _loadUsers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'User "${user.fullName}" (${user.email}) has been permanently deleted.',
            style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to delete user: $e',
            style: const TextStyle(fontFamily: 'Inter', color: Colors.white),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingUserId = null);
    }
  }

  Future<void> _handleCreateBuyer() async {
    if (!_createFormKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final newBuyer = await _service.createBuyerByAdmin(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        customPassword: _passwordController.text,
      );

      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _passwordController.clear();

      await _loadUsers();

      if (!mounted) return;
      setState(() => _showCreateForm = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created Buyer Account! Assigned ID: ${newBuyer.buyerId}',
            style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception: ', ''),
            style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _allUsers
        .where((u) =>
            u.businessProfileId == null ||
            u.businessStatus == null ||
            u.businessStatus == 'none')
        .length;
    final buyersCount = _allUsers.where((u) => u.isBuyer).length;
    final sellersCount = _allUsers.where((u) => u.isSeller).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'User Accounts & Form 1 Review',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            Text(
              'Inspect Form 1 registrations & delete unlegit users',
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.secondaryText,
                  fontSize: 11),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.navy),
            tooltip: 'Refresh User List',
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Input
            TextField(
              controller: _searchController,
              style: const TextStyle(
                  fontFamily: 'Inter', color: AppColors.navy, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by name, email, phone, or Buyer ID...',
                hintStyle: const TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.secondaryText,
                    fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.secondaryText, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            size: 18, color: AppColors.secondaryText),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.cardBackground,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All Users (${_allUsers.length})'),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      'pending_form2', 'Pending Form 2 ($pendingCount)',
                      isAlert: pendingCount > 0),
                  const SizedBox(width: 8),
                  _buildFilterChip('buyer', 'Buyers ($buyersCount)'),
                  const SizedBox(width: 8),
                  _buildFilterChip('seller', 'Sellers ($sellersCount)'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Manual Buyer Creation Toggle Card
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () =>
                        setState(() => _showCreateForm = !_showCreateForm),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.person_add_alt_1_outlined,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Manual Buyer ID Generator (Optional)',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.navy,
                                  fontSize: 13),
                            ),
                          ),
                          Icon(
                            _showCreateForm
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: AppColors.secondaryText,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showCreateForm) ...[
                    const Divider(height: 1, color: AppColors.border),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _createFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _nameController,
                              validator: (v) =>
                                  v!.isEmpty ? 'Full name required' : null,
                              style: const TextStyle(
                                  fontFamily: 'Inter', color: AppColors.navy),
                              decoration: const InputDecoration(
                                labelText: 'Buyer Full Name',
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(8))),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _emailController,
                                    validator: (v) =>
                                        v!.isEmpty ? 'Email required' : null,
                                    style: const TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.navy),
                                    decoration: const InputDecoration(
                                      labelText: 'Email Address',
                                      filled: true,
                                      fillColor: AppColors.background,
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(8))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _phoneController,
                                    style: const TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.navy),
                                    decoration: const InputDecoration(
                                      labelText: 'Nepal Phone',
                                      filled: true,
                                      fillColor: AppColors.background,
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(8))),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              validator: (v) => v == null || v.length < 8
                                  ? 'Password must be at least 8 characters'
                                  : null,
                              style: const TextStyle(
                                  fontFamily: 'Inter', color: AppColors.navy),
                              decoration: const InputDecoration(
                                labelText: 'Initial Password',
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(8))),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isCreating ? null : _handleCreateBuyer,
                                icon: _isCreating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.badge_outlined,
                                        size: 18),
                                label: Text(
                                  _isCreating
                                      ? 'GENERATING...'
                                      : 'GENERATE BUYER ID',
                                  style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Header for registered users list
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'REGISTERED USERS (${_filteredUsers.length})',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _selectedFilter == 'pending_form2'
                      ? 'Showing Form 1 Only'
                      : 'Role: ${_selectedFilter.toUpperCase()}',
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.secondaryText,
                      fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Users List
            _isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                  )
                : _filteredUsers.isEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 40, horizontal: 20),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.people_outline,
                                color: AppColors.secondaryText, size: 48),
                            const SizedBox(height: 10),
                            const Text(
                              'No registered accounts match your criteria.',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppColors.secondaryText,
                                  fontSize: 13),
                            ),
                            if (_searchQuery.isNotEmpty ||
                                _selectedFilter != 'all') ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedFilter = 'all';
                                    _searchController.clear();
                                  });
                                },
                                child: const Text('Reset Filters',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredUsers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          return _buildUserCard(user);
                        },
                      ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, {bool isAlert = false}) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected
            ? Colors.white
            : (isAlert ? AppColors.amber : AppColors.navy),
      ),
      selectedColor: isAlert ? AppColors.amber : AppColors.navy,
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? (isAlert ? AppColors.amber : AppColors.navy)
              : (isAlert
                  ? AppColors.amber.withValues(alpha: 0.5)
                  : AppColors.border),
        ),
      ),
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }

  Widget _buildUserCard(Profile user) {
    final isDeleting = _deletingUserId == user.id;
    final isBuyer = user.isBuyer;
    final isPendingForm2 = user.businessProfileId == null ||
        user.businessStatus == null ||
        user.businessStatus == 'none';
    final isApproved = user.businessStatus == 'approved';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPendingForm2
              ? AppColors.amber.withValues(alpha: 0.4)
              : AppColors.border,
          width: isPendingForm2 ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Role Badge, Name, and Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Role Icon Box
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isBuyer
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isBuyer
                      ? Icons.person_outline_rounded
                      : Icons.storefront_outlined,
                  color: isBuyer ? AppColors.primary : AppColors.amber,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.fullName,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isBuyer
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : AppColors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isBuyer ? 'BUYER' : 'SELLER',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color:
                                  isBuyer ? AppColors.primary : AppColors.amber,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.secondaryText,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPendingForm2
                      ? AppColors.amber.withValues(alpha: 0.12)
                      : (isApproved
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.primary.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPendingForm2
                          ? Icons.pending_outlined
                          : (isApproved
                              ? Icons.check_circle_outline
                              : Icons.schedule),
                      size: 12,
                      color: isPendingForm2
                          ? AppColors.amber
                          : (isApproved
                              ? AppColors.success
                              : AppColors.primary),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPendingForm2
                          ? 'PENDING FORM 2'
                          : (isApproved ? 'VERIFIED' : 'FORM 2 SUBMITTED'),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isPendingForm2
                            ? AppColors.amber
                            : (isApproved
                                ? AppColors.success
                                : AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),

          // User info row: Phone, Buyer ID, Registration Time
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (user.phone != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone_outlined,
                        size: 14, color: AppColors.secondaryText),
                    const SizedBox(width: 4),
                    Text(
                      NepalPhoneHelper.formatDisplay(user.phone!),
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.navy,
                          fontSize: 12),
                    ),
                  ],
                ),
              if (user.buyerId != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      user.buyerId!,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ],
                ),
              if (user.createdAt != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 14, color: AppColors.secondaryText),
                    const SizedBox(width: 4),
                    Text(
                      ServerTimeService.formatNepalTime(user.createdAt!),
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.secondaryText,
                          fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),

          if (isPendingForm2) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: AppColors.amber.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppColors.amber),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Completed Form 1 (Role & Credentials). Has not filled Form 2 (Business Details) yet. You can delete this user now if unlegit.',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: AppColors.amber),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action Button: DELETE UNLEGIT USER
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: isDeleting ? null : () => _handleDeleteUser(user),
                icon: isDeleting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.danger))
                    : const Icon(Icons.person_remove_rounded,
                        color: AppColors.danger, size: 16),
                label: Text(
                  isDeleting ? 'DELETING...' : 'DELETE UNLEGIT USER',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
