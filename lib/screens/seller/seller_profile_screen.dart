// Screen: Seller Profile & Account Information Management
// Allows sellers/dealers to view all account and business details, monitor verification status, and edit/update their profile.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bid_app/config/supabase_config.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/screens/buyer/business_registration_screen.dart';
import 'package:bid_app/screens/auth/login_screen.dart';

class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({super.key});

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  final AuctionService _service = AuctionService();

  bool _isLoading = true;
  BusinessProfile? _businessProfile;
  List<Auction> _myAuctions = [];
  StreamSubscription<List<BusinessProfile>>? _businessSub;
  StreamSubscription<Profile>? _profileSub;

  @override
  void initState() {
    super.initState();
    _loadData();

    _businessSub = _service.businessProfileStream.listen((_) {
      if (mounted) _loadData();
    });

    _profileSub = _service.profileStream.listen((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _businessSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final currentUserId = _service.currentUser.id;

    final bp = await _service.fetchBusinessProfileForUser(currentUserId);
    final allAuctions = await _service.fetchAuctions();
    final user = _service.currentUser;

    final sellerAuctions = allAuctions.where((a) {
      return a.createdBy == currentUserId ||
          a.createdBy == null ||
          user.isSeller ||
          user.isAdmin ||
          user.isBusiness;
    }).toList();

    if (mounted) {
      setState(() {
        _businessProfile = bp;
        _myAuctions = sellerAuctions;
        _isLoading = false;
      });
    }
  }

  void _showEditPersonalProfileModal() {
    final nameController = TextEditingController(text: _service.currentUser.fullName);
    final phoneController = TextEditingController(text: _service.currentUser.phone ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 24,
            left: 20,
            right: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Edit Personal Profile',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Please enter your full name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Contact Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setModalState(() => isSaving = true);
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(ctx);
                          try {
                            await _service.updateUserProfile(
                              fullName: nameController.text.trim(),
                              phone: phoneController.text.trim(),
                            );
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('✅ Personal profile updated successfully!'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                            if (mounted) setState(() {});
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Error updating profile: $e'),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDocumentPreview(String title, String path) {
    String publicUrl = path;
    if (!path.startsWith('http')) {
      publicUrl = SupabaseConfig.client.storage.from('business-documents').getPublicUrl(path);
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.navy,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  publicUrl,
                  height: 280,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    color: Colors.grey.shade100,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'Document file submitted securely.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Path: $path',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _service.currentUser;
    final liveCount = _myAuctions.where((a) => a.status == 'live').length;
    final soldCount = _myAuctions.where((a) => a.status == 'finalised' || a.status == 'ended').length;

    final businessStatus = _businessProfile?.status ?? user.businessStatus ?? 'pending';
    final isApproved = businessStatus == 'approved' || user.isApprovedBusiness;
    final isRejected = businessStatus == 'rejected';
    final isPending = businessStatus == 'pending' && !isApproved;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Seller Account & Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh Profile',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  children: [
                    // Top Hero Profile Header
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                      child: Column(
                        children: [
                          // Avatar
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 44,
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'S',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _showEditPersonalProfileModal,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.edit_rounded,
                                    size: 16,
                                    color: AppColors.navy,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Full Name
                          Text(
                            user.fullName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Email
                          Text(
                            user.email,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Role & Verification Status Badges
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.storefront_rounded, size: 14, color: Colors.white),
                                    const SizedBox(width: 6),
                                    Text(
                                      _businessProfile?.businessType.toUpperCase() ?? 'DEALER / SELLER',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isApproved
                                      ? AppColors.success.withValues(alpha: 0.2)
                                      : isRejected
                                          ? AppColors.danger.withValues(alpha: 0.2)
                                          : AppColors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isApproved
                                        ? AppColors.success
                                        : isRejected
                                            ? AppColors.danger
                                            : AppColors.amber,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isApproved
                                          ? Icons.verified_rounded
                                          : isRejected
                                              ? Icons.cancel_rounded
                                              : Icons.hourglass_top_rounded,
                                      size: 14,
                                      color: isApproved
                                          ? AppColors.success
                                          : isRejected
                                              ? AppColors.danger
                                              : AppColors.amber,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isApproved
                                          ? 'VERIFIED & ACTIVE'
                                          : isRejected
                                              ? 'REGISTRATION REJECTED'
                                              : 'PENDING ADMIN APPROVAL',
                                      style: TextStyle(
                                        color: isApproved
                                            ? AppColors.success
                                            : isRejected
                                                ? AppColors.danger
                                                : AppColors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Quick Action Button
                          OutlinedButton.icon(
                            onPressed: _showEditPersonalProfileModal,
                            icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 16),
                            label: const Text(
                              'Edit Personal Details',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white38),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Admin Status Feedback Alert Card
                          if (isRejected) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 22),
                                      SizedBox(width: 10),
                                      Text(
                                        'Admin Review Feedback',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _businessProfile?.rejectionReason ??
                                        'Please update your documents or correct registration details and resubmit.',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.navy,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      final res = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => BusinessRegistrationScreen(
                                            existingProfile: _businessProfile,
                                          ),
                                        ),
                                      );
                                      if (res == true) _loadData();
                                    },
                                    icon: const Icon(Icons.replay_rounded, color: Colors.white, size: 18),
                                    label: const Text(
                                      'Resubmit Business Profile',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.danger,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ] else if (isPending) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.amber.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.access_time_filled_rounded, color: AppColors.amber, size: 24),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Application Under Review / Pending Edit',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            color: AppColors.navy,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _businessProfile?.rejectionReason != null && _businessProfile!.rejectionReason!.isNotEmpty
                                        ? 'Admin Note: ${_businessProfile!.rejectionReason}'
                                        : 'Our admin team is verifying your registration. You can edit your details and update documents below if needed.',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.navy,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      final res = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => BusinessRegistrationScreen(
                                            existingProfile: _businessProfile,
                                          ),
                                        ),
                                      );
                                      if (res == true) _loadData();
                                    },
                                    icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 18),
                                    label: const Text(
                                      'Edit / Update Business Details',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.amber,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Seller KPI Overview
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatTile(
                                  label: 'Auctions Listed',
                                  value: '${_myAuctions.length}',
                                  icon: Icons.two_wheeler_rounded,
                                  color: Colors.blueAccent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildStatTile(
                                  label: 'Live Now',
                                  value: '$liveCount',
                                  icon: Icons.gavel_rounded,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildStatTile(
                                  label: 'Vehicles Sold',
                                  value: '$soldCount',
                                  icon: Icons.verified_rounded,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Card 1: Account & Contact Details
                          _buildSectionCard(
                            title: 'Account Information',
                            icon: Icons.badge_outlined,
                            trailing: IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                              tooltip: 'Edit Personal Details',
                              onPressed: _showEditPersonalProfileModal,
                            ),
                            children: [
                              _buildInfoRow('Account Holder', user.fullName),
                              _buildInfoRow('Email Address', user.email),
                              _buildInfoRow('Phone Number', user.phone?.isNotEmpty == true ? user.phone! : 'Not specified'),
                              _buildInfoRow('Account Role', 'Seller / Dealer'),
                              _buildInfoRow(
                                'Account ID',
                                user.id,
                                isMonospace: true,
                                trailing: IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.grey),
                                  tooltip: 'Copy ID',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: user.id));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Account ID copied to clipboard!')),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Card 2: Dealership / Business Profile Details
                          if (_businessProfile != null) ...[
                            _buildSectionCard(
                              title: 'Dealership & Business Profile',
                              icon: Icons.business_outlined,
                              trailing: TextButton.icon(
                                onPressed: () async {
                                  final res = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BusinessRegistrationScreen(
                                        existingProfile: _businessProfile,
                                      ),
                                    ),
                                  );
                                  if (res == true) _loadData();
                                },
                                icon: const Icon(Icons.edit_rounded, size: 16, color: AppColors.primary),
                                label: const Text('Edit', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              ),
                              children: [
                                _buildInfoRow('Company Name', _businessProfile!.companyName),
                                _buildInfoRow('Account Type', _businessProfile!.businessType.toUpperCase()),
                                if (_businessProfile!.dealershipBrand != null &&
                                    _businessProfile!.dealershipBrand!.isNotEmpty)
                                  _buildInfoRow('Authorized Brand', _businessProfile!.dealershipBrand!),
                                _buildInfoRow('PAN / VAT Number', _businessProfile!.companyPanVatNumber),
                                _buildInfoRow('Company Phone', _businessProfile!.companyPhoneNumber),
                                _buildInfoRow('Bank Name', _businessProfile!.companyBankName),
                                _buildInfoRow('Account Number', _businessProfile!.companyAccountNumber),
                                const Divider(height: 24),
                                const Text(
                                  'Authorized Representatives',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.navy,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildInfoRow('Primary Contact', '${_businessProfile!.primaryPersonName} (${_businessProfile!.primaryPersonPhone})'),
                                _buildInfoRow('Primary Email', _businessProfile!.primaryPersonEmail),
                                if (_businessProfile!.secondaryPersonName != null &&
                                    _businessProfile!.secondaryPersonName!.isNotEmpty) ...[
                                  _buildInfoRow('Secondary Contact', '${_businessProfile!.secondaryPersonName} (${_businessProfile!.secondaryPersonPhone ?? ""})'),
                                  if (_businessProfile!.secondaryPersonEmail != null &&
                                      _businessProfile!.secondaryPersonEmail!.isNotEmpty)
                                    _buildInfoRow('Secondary Email', _businessProfile!.secondaryPersonEmail!),
                                ],
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Card 3: Business Documents & Attachments
                            _buildSectionCard(
                              title: 'Verification Documents',
                              icon: Icons.folder_shared_outlined,
                              children: [
                                _buildDocumentTile(
                                  label: 'PAN / VAT Certificate',
                                  path: _businessProfile!.companyPanVatDocPath,
                                  icon: Icons.file_present_rounded,
                                ),
                                const SizedBox(height: 8),
                                _buildDocumentTile(
                                  label: 'Company Registration Document',
                                  path: _businessProfile!.companyRegDocPath,
                                  icon: Icons.verified_user_outlined,
                                ),
                                const SizedBox(height: 8),
                                _buildDocumentTile(
                                  label: 'Payment QR Code',
                                  path: _businessProfile!.companyQrPath,
                                  icon: Icons.qr_code_2_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ] else ...[
                            // No Business Profile Registered Yet
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.business_center_outlined, size: 48, color: Colors.grey),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No Business Details Registered',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Register your Dealer or Reconditioner business to gain verified status and sell bikes seamlessly.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.secondaryText, fontSize: 13),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      final res = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const BusinessRegistrationScreen(),
                                        ),
                                      );
                                      if (res == true) _loadData();
                                    },
                                    icon: const Icon(Icons.add_business_rounded, color: Colors.white),
                                    label: const Text('Complete Business Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Security / Logout Section
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.logout_rounded, color: Colors.red),
                                  ),
                                  title: const Text(
                                    'Log Out Account',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Sign out of this session and return to login screen',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                                  onTap: () async {
                                    final nav = Navigator.of(context);
                                    try {
                                      await SupabaseConfig.client.auth.signOut();
                                    } catch (_) {}
                                    nav.pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                                      (route) => false,
                                    );
                                  },
                                ),
                              ],
                            ),
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

  Widget _buildStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
              if (trailing != null) trailing,
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isMonospace = false, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: AppColors.secondaryText,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: isMonospace ? 'monospace' : 'Inter',
                color: AppColors.navy,
                fontSize: isMonospace ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildDocumentTile({
    required String label,
    required String? path,
    required IconData icon,
  }) {
    final hasFile = path != null && path.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: hasFile ? AppColors.primary : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
                Text(
                  hasFile ? 'Uploaded and verified' : 'Not uploaded',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: hasFile ? AppColors.success : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (hasFile)
            TextButton(
              onPressed: () => _showDocumentPreview(label, path),
              child: const Text('View', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}
