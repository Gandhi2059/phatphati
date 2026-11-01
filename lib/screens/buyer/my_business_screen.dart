// My Business Profile Screen
// Shows status banner, profile details, and edit capability (unless suspended)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/screens/buyer/business_registration_screen.dart';

class MyBusinessScreen extends StatefulWidget {
  const MyBusinessScreen({super.key});

  @override
  State<MyBusinessScreen> createState() => _MyBusinessScreenState();
}

class _MyBusinessScreenState extends State<MyBusinessScreen> {
  bool _isLoading = true;
  BusinessProfile? _businessProfile;
  StreamSubscription<Profile>? _profileSub;
  StreamSubscription<List<BusinessProfile>>? _businessSub;

  @override
  void initState() {
    super.initState();
    _loadProfile();

    _profileSub = AuctionService().profileStream.listen((_) {
      if (mounted) _loadProfile();
    });

    _businessSub = AuctionService().businessProfileStream.listen((_) {
      if (mounted) _loadProfile();
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _businessSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final userId = AuctionService().currentUser.id;
    final p = await AuctionService().fetchBusinessProfileForUser(userId);
    if (mounted) {
      setState(() {
        _businessProfile = p;
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.danger;
      case 'suspended':
        return AppColors.amber;
      case 'pending':
      default:
        return AppColors.amber;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.verified_outlined;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'suspended':
        return Icons.block_outlined;
      case 'pending':
      default:
        return Icons.hourglass_top_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'My Business Profile',
          style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _businessProfile == null
              ? _buildEmptyState()
              : _buildProfileContent(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.business_center_outlined, size: 56, color: AppColors.secondaryText),
            const SizedBox(height: 16),
            const Text(
              'No Business Registered',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Register your Dealer or Recondition business to enable business buying and selling privileges.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BusinessRegistrationScreen()),
                );
                if (res == true) _loadProfile();
              },
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Register Business', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileContent() {
    final p = _businessProfile!;
    final color = _getStatusColor(p.status);
    final icon = _getStatusIcon(p.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STATUS: ${p.status.toUpperCase()}',
                        style: TextStyle(fontFamily: 'Inter', color: color, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (p.status == 'pending') ...[
                        const Text(
                          'Your profile is under admin review. You can edit your details and update documents below.',
                          style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
                        ),
                        if (p.rejectionReason != null && p.rejectionReason!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Admin Note: ${p.rejectionReason}',
                              style: const TextStyle(fontFamily: 'Inter', color: AppColors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                      ],
                      if (p.status == 'approved')
                        const Text(
                          'Verified Business Member. You have active business trading privileges.',
                          style: TextStyle(fontFamily: 'Inter', color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      if (p.status == 'rejected' && p.rejectionReason != null)
                        Text(
                          'Reason: ${p.rejectionReason}',
                          style: const TextStyle(fontFamily: 'Inter', color: AppColors.danger, fontSize: 13),
                        ),
                      if (p.status == 'suspended')
                        const Text(
                          'Your account has been suspended by an administrator. Please contact support.',
                          style: TextStyle(fontFamily: 'Inter', color: AppColors.amber, fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Button (Edit / Resubmit if not suspended)
          if (p.status != 'suspended') ...[
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BusinessRegistrationScreen(existingProfile: p),
                    ),
                  );
                  if (res == true) _loadProfile();
                },
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                label: Text(
                  p.status == 'rejected' ? 'Resubmit Business Profile' : 'Edit Business Details',
                  style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Details List
          _buildDetailCard(
            title: 'Business Overview',
            icon: Icons.store_outlined,
            items: {
              'Company Name': p.companyName,
              'Business Type': p.businessType.toUpperCase(),
              if (p.dealershipBrand != null) 'Dealership Brand': p.dealershipBrand!,
              'PAN / VAT Number': p.companyPanVatNumber,
              'Company Phone': p.companyPhoneNumber,
            },
          ),
          const SizedBox(height: 16),

          _buildDetailCard(
            title: 'Banking Details',
            icon: Icons.account_balance_outlined,
            items: {
              'Bank Name': p.companyBankName,
              'Account Number': p.companyAccountNumber,
            },
          ),
          const SizedBox(height: 16),

          _buildDetailCard(
            title: 'Authorised Contacts',
            icon: Icons.people_outlined,
            items: {
              'Primary Person': p.primaryPersonName,
              'Primary Email': p.primaryPersonEmail,
              'Primary Phone': p.primaryPersonPhone,
              if (p.secondaryPersonName != null && p.secondaryPersonName!.isNotEmpty) 'Secondary Person': p.secondaryPersonName!,
              if (p.secondaryPersonEmail != null && p.secondaryPersonEmail!.isNotEmpty) 'Secondary Email': p.secondaryPersonEmail!,
              if (p.secondaryPersonPhone != null && p.secondaryPersonPhone!.isNotEmpty) 'Secondary Phone': p.secondaryPersonPhone!,
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard({
    required String title,
    required IconData icon,
    required Map<String, String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.navy, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: 20),
          ...items.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key, style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13)),
                    Text(entry.value, style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
