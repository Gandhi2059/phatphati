// Admin Deposit Verification & Payment Management Screen
// Lists deposit records, previews receipt images with 1-hour signed URLs, verifies/rejects payments, sets vehicle status to 'reserved', and manages platform bank details.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminDepositVerificationScreen extends StatefulWidget {
  const AdminDepositVerificationScreen({super.key});

  @override
  State<AdminDepositVerificationScreen> createState() => _AdminDepositVerificationScreenState();
}

class _AdminDepositVerificationScreenState extends State<AdminDepositVerificationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<DepositRecord> _records = [];
  StreamSubscription<List<DepositRecord>>? _depositSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
    _depositSub = AuctionService().depositRecordStream.listen((records) {
      if (mounted) {
        setState(() {
          _records = records;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _depositSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final list = await AuctionService().fetchAllDepositRecordsForAdmin();

    if (mounted) {
      setState(() {
        _records = list;
        _isLoading = false;
      });
    }
  }

  List<DepositRecord> _filterByStatus(String status) {
    if (status == 'pending_verification') {
      return _records.where((r) =>
          r.status == 'submitted_for_verification' ||
          r.status == 'under_review' ||
          r.status == 'pending_deposit' ||
          r.status == 'awaiting_payment' ||
          (r.latestEvidencePath != null && r.status != 'verified' && r.status != 'rejected') ||
          (r.submissions.isNotEmpty && r.status != 'verified' && r.status != 'rejected')
      ).toList();
    }
    if (status == 'verified') {
      return _records.where((r) => r.status == 'verified').toList();
    }
    if (status == 'rejected') {
      return _records.where((r) => r.status == 'rejected').toList();
    }
    return _records.where((r) => r.status == status).toList();
  }

  Future<void> _handleVerify(DepositRecord record) async {
    final vehicleTitle = record.auction?.title ?? 'Vehicle';
    final buyerName = record.winnerProfile?.fullName ?? 'Winning Buyer';
    final buyerId = record.winnerProfile?.buyerId ?? (record.winningBuyerId.length > 8 ? record.winningBuyerId.substring(0, 8) : record.winningBuyerId);

    final instructionsController = TextEditingController(
      text: 'Congratulations $buyerName! Your 10% booking deposit of NPR ${record.depositAmount.toStringAsFixed(0)} is verified. "$vehicleTitle" is officially reserved in your name.\n\nNext Steps:\n1. Visit our Showroom at Kathmandu within 7 days.\n2. Present your original Nepali citizenship certificate.\n3. Pay the remaining 90% balance (NPR ${record.remainingBalance.toStringAsFixed(0)}) upon physical bluebook transfer and vehicle handover.\n\nHelpline: +977-9800000000',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppColors.success),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Verify Deposit & Send Message',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Buyer: $buyerName ($buyerId)', style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('Vehicle: $vehicleTitle', style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      '10% Deposit: NPR ${record.depositAmount.toStringAsFixed(2)} | 90% Balance: NPR ${record.remainingBalance.toStringAsFixed(2)}',
                      style: const TextStyle(fontFamily: 'Inter', color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Custom Message & Handover Instructions for Winner:',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: instructionsController,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter specific handover instructions, showroom address, deadline...',
                  hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText),
                  filled: true,
                  fillColor: AppColors.cardBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
            child: const Text('Verify & Send Message', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await AuctionService().adminVerifyDeposit(
        depositRecordId: record.id,
        action: 'verify',
        nextStepInstructions: instructionsController.text.trim(),
        winningBuyerId: record.winningBuyerId,
        sellerUserId: record.auction?.createdBy,
        vehicleTitle: record.auction?.title,
        depositAmount: record.depositAmount,
        auctionId: record.auctionId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('10% Deposit verified, vehicle reserved, and custom message sent!'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _handleReject(DepositRecord record) async {
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject Deposit Evidence', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
          decoration: InputDecoration(
            hintText: 'Enter reason for rejection (e.g. illegible receipt, incorrect amount)...',
            hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText),
            filled: true,
            fillColor: AppColors.cardBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            child: const Text('Reject Submission', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (result != true || reasonController.text.trim().isEmpty) return;

    try {
      await AuctionService().adminVerifyDeposit(
        depositRecordId: record.id,
        action: 'reject',
        rejectionReason: reasonController.text.trim(),
        winningBuyerId: record.winningBuyerId,
        sellerUserId: record.auction?.createdBy,
        vehicleTitle: record.auction?.title,
        depositAmount: record.depositAmount,
        auctionId: record.auctionId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deposit evidence rejected.'), backgroundColor: AppColors.danger),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _editInstructions(DepositRecord record) async {
    final controller = TextEditingController(text: record.nextStepInstructions ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Update Next-Step Instructions', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
          decoration: InputDecoration(
            hintText: 'Enter updated instructions for buyer...',
            hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText),
            filled: true,
            fillColor: AppColors.cardBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Save Instructions', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      await AuctionService().adminUpdateDepositInstructions(
        depositRecordId: record.id,
        nextStepInstructions: controller.text.trim(),
      );
      _loadData();
    }
  }

  void _viewEvidence(String path) async {
    final signedUrl = await AuctionService().getSignedUrl('deposit-evidence', path);
    final isPdf = path.toLowerCase().endsWith('.pdf');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                        color: isPdf ? Colors.redAccent : AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPdf ? 'PDF Payment Voucher' : 'Payment Evidence Receipt',
                        style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.navy),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isPdf) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 64),
                      const SizedBox(height: 12),
                      const Text(
                        'PDF Document Attached',
                        style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse(signedUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text(
                          'Open / Download PDF Document',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      signedUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('Failed to load evidence image', style: TextStyle(fontFamily: 'Inter', color: AppColors.danger)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openPaymentSettingsDialog() async {
    final rawSettings = await AuctionService().fetchPlatformPaymentSettings();
    final depositPctController = TextEditingController(text: (rawSettings?.depositPercentage ?? 10.0).toString());
    final deadlineMinsController = TextEditingController(text: (rawSettings?.paymentDeadlineMinutes ?? 30).toString());
    final bankController = TextEditingController(text: rawSettings?.bankName ?? 'Global IME Bank Nepal');
    final accountNameController = TextEditingController(text: rawSettings?.accountName ?? 'Auction Platform Pvt Ltd');
    final accountNoController = TextEditingController(text: rawSettings?.accountNumber ?? '0010100029384');
    final instructionsController = TextEditingController(text: rawSettings?.depositInstructions ?? 'Please pay deposit booking amount within deadline.');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            title: const Text('Platform Payment Settings', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: depositPctController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                          decoration: const InputDecoration(labelText: 'Deposit % (Default: 10%)', labelStyle: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: deadlineMinsController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                          decoration: const InputDecoration(labelText: 'Deadline (Mins)', labelStyle: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bankController,
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                    decoration: const InputDecoration(labelText: 'Bank Name', labelStyle: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: accountNameController,
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                    decoration: const InputDecoration(labelText: 'Account Name', labelStyle: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: accountNoController,
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                    decoration: const InputDecoration(labelText: 'Account Number', labelStyle: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: instructionsController,
                    maxLines: 2,
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                    decoration: const InputDecoration(labelText: 'Deposit Instructions', labelStyle: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final pct = double.tryParse(depositPctController.text.trim()) ?? 10.0;
                  final mins = int.tryParse(deadlineMinsController.text.trim()) ?? 30;

                  await AuctionService().updatePlatformPaymentSettings(
                    depositPercentage: pct,
                    paymentDeadlineMinutes: mins,
                    bankName: bankController.text.trim(),
                    accountName: accountNameController.text.trim(),
                    accountNumber: accountNoController.text.trim(),
                    depositInstructions: instructionsController.text.trim(),
                  );

                  if (context.mounted) Navigator.pop(ctx);
                  _loadData();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                child: const Text('Save Settings', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('Deposit Verification', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.navy),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.navy),
            tooltip: 'Platform Payment Settings',
            onPressed: _openPaymentSettingsDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.secondaryText,
          labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.normal),
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Verified'),
            Tab(text: 'Rejected'),
            Tab(text: 'All Records'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRecordList(_filterByStatus('pending_verification')),
                _buildRecordList(_filterByStatus('verified')),
                _buildRecordList(_filterByStatus('rejected')),
                _buildRecordList(_records),
              ],
            ),
    );
  }

  Widget _buildRecordList(List<DepositRecord> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text('No deposit records in this view.', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final r = list[i];
        final isVerified = r.status == 'verified';

        return Card(
          color: AppColors.cardBackground,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        r.bookingReference,
                        style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isVerified ? AppColors.success.withValues(alpha: 0.1) : AppColors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isVerified ? 'DEPOSIT VERIFIED' : r.status.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: isVerified ? AppColors.success : AppColors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Vehicle: ${r.auction?.title ?? "Auction ${r.auctionId.substring(0, 6)}"}',
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                // Buyer Details
                Row(
                  children: [
                    const Icon(Icons.person_pin_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Buyer: ${r.winnerProfile?.fullName ?? "Winning Buyer"} (${r.winnerProfile?.buyerId ?? (r.winningBuyerId.length > 8 ? r.winningBuyerId.substring(0, 8) : r.winningBuyerId)})'
                        '${r.winnerProfile?.phone != null && r.winnerProfile!.phone!.isNotEmpty ? " • 📞 ${r.winnerProfile!.phone}" : ""}',
                        style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Winning Bid: NPR ${r.winningAmount.toStringAsFixed(2)}', style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13)),
                Text('10% Deposit: NPR ${r.depositAmount.toStringAsFixed(2)} | 90% Balance: NPR ${r.remainingBalance.toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 13)),
                if (r.latestTransactionReference != null)
                  Text('Txn Ref / UTR: ${r.latestTransactionReference}', style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13)),

                // Custom message if verified or rejected
                if (r.nextStepInstructions != null && r.nextStepInstructions!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.mark_email_read_rounded, size: 14, color: AppColors.success),
                            SizedBox(width: 6),
                            Text('Custom Instructions Sent to Winner:', style: TextStyle(fontFamily: 'Inter', color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(r.nextStepInstructions!, style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 12, height: 1.3)),
                      ],
                    ),
                  ),
                ],

                const Divider(color: AppColors.border, height: 20),

                // Evidence buttons & Action buttons
                Builder(
                  builder: (_) {
                    final effectiveEvidencePath = (r.latestEvidencePath != null && r.latestEvidencePath!.isNotEmpty)
                        ? r.latestEvidencePath!
                        : (r.submissions.isNotEmpty && r.submissions.last.evidenceDocPath.isNotEmpty ? r.submissions.last.evidenceDocPath : null);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (effectiveEvidencePath != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _viewEvidence(effectiveEvidencePath),
                                  icon: Icon(
                                    effectiveEvidencePath.toLowerCase().endsWith('.pdf')
                                        ? Icons.picture_as_pdf_rounded
                                        : Icons.receipt_outlined,
                                    size: 16,
                                    color: effectiveEvidencePath.toLowerCase().endsWith('.pdf') ? Colors.redAccent : AppColors.navy,
                                  ),
                                  label: Text(
                                    effectiveEvidencePath.toLowerCase().endsWith('.pdf') ? 'View Evidence (PDF)' : 'View Evidence (Photo)',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: effectiveEvidencePath.toLowerCase().endsWith('.pdf') ? Colors.redAccent : AppColors.navy,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.hourglass_empty_rounded, size: 14, color: AppColors.amber),
                                    SizedBox(width: 4),
                                    Text(
                                      'Awaiting Buyer Evidence',
                                      style: TextStyle(fontFamily: 'Inter', color: AppColors.amber, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (r.status != 'verified') ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: ElevatedButton.icon(
                                  onPressed: () => _handleVerify(r),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.check_circle_outline, size: 16),
                                  label: const Text('Verify & Reserve', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: () => _handleReject(r),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.danger,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.close_rounded, size: 16),
                                  label: const Text('Reject', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (r.status == 'verified') ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => _editInstructions(r),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.edit_note_outlined, size: 16),
                            label: const Text('Edit Instructions', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 12)),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
