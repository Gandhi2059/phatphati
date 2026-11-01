// Deposit Details, Dynamic Bank QR & Evidence Upload Screen for Winning Buyers
// Displays platform bank details, dynamic QR code generation, 10% deposit calculations,
// countdown timer, dual photo & PDF evidence upload, and admin verification status tracking.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/widgets/countdown_timer_widget.dart';

class DepositDetailsScreen extends StatefulWidget {
  final String auctionId;

  const DepositDetailsScreen({super.key, required this.auctionId});

  @override
  State<DepositDetailsScreen> createState() => _DepositDetailsScreenState();
}

class _DepositDetailsScreenState extends State<DepositDetailsScreen> {
  bool _isLoading = true;
  DepositRecord? _depositRecord;
  PlatformPaymentSettings? _paymentSettings;
  String? _platformQrSignedUrl;
  StreamSubscription<List<DepositRecord>>? _depositStreamSub;

  final _formKey = GlobalKey<FormState>();
  String _paymentMethod = 'bank_transfer';
  final _txnRefController = TextEditingController();
  final _notesController = TextEditingController();

  // Evidence state (supports image or PDF)
  Uint8List? _evidenceBytes;
  String? _evidenceFileName;
  bool _isPdf = false;
  int? _evidenceFileSizeBytes;

  bool _isSubmitting = false;
  String? _errorMessage;
  int _selectedQrTab = 0; // 0: Dynamic QR with amount, 1: Platform Bank QR

  final ImagePicker _picker = ImagePicker();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadData();
    _depositStreamSub = AuctionService().depositRecordStream.listen((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _depositStreamSub?.cancel();
    _txnRefController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final record = await AuctionService().fetchDepositRecordForAuction(widget.auctionId);
    final settings = await AuctionService().fetchPlatformPaymentSettings();

    String? qrUrl;
    final path = settings?.qrImagePath;
    if (path != null && path.isNotEmpty) {
      qrUrl = await AuctionService().getSignedUrl('business-documents', path);
    }

    if (mounted) {
      setState(() {
        _depositRecord = record;
        _paymentSettings = settings;
        _platformQrSignedUrl = qrUrl;
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('$label copied to clipboard!'),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickPhoto() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Upload Receipt Photo',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: const Text('Choose from Gallery', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                    if (file != null) {
                      final bytes = await file.readAsBytes();
                      setState(() {
                        _evidenceBytes = bytes;
                        _evidenceFileName = file.name;
                        _isPdf = false;
                        _evidenceFileSizeBytes = bytes.length;
                        _errorMessage = null;
                      });
                    }
                  } catch (e) {
                    _showError('Failed to select image: $e');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                title: const Text('Take Photo with Camera', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final XFile? file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                    if (file != null) {
                      final bytes = await file.readAsBytes();
                      setState(() {
                        _evidenceBytes = bytes;
                        _evidenceFileName = file.name;
                        _isPdf = false;
                        _evidenceFileSizeBytes = bytes.length;
                        _errorMessage = null;
                      });
                    }
                  } catch (e) {
                    _showError('Failed to capture photo: $e');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPdf() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.xFile.readAsBytes();
        final size = await file.xFile.length();
        setState(() {
          _evidenceBytes = bytes;
          _evidenceFileName = file.name;
          _isPdf = true;
          _evidenceFileSizeBytes = size;
          _errorMessage = null;
        });
      }
    } catch (e) {
      _showError('Failed to pick PDF document: $e');
    }
  }

  void _clearEvidence() {
    setState(() {
      _evidenceBytes = null;
      _evidenceFileName = null;
      _isPdf = false;
      _evidenceFileSizeBytes = null;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  Future<void> _handleSubmitEvidence() async {
    if (_depositRecord == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (_evidenceBytes == null) {
      if (kDebugMode) {
        _evidenceBytes = Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
          0x42, 0x60, 0x82,
        ]);
        _evidenceFileName = 'demo_voucher.png';
        _isPdf = false;
      } else {
        setState(() => _errorMessage = 'Please select a photo receipt or PDF document to upload.');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await AuctionService().submitDepositEvidence(
        depositRecordId: _depositRecord!.id,
        paymentMethod: _paymentMethod,
        transactionReference: _txnRefController.text.trim().isNotEmpty ? _txnRefController.text.trim() : null,
        evidenceBytes: _evidenceBytes!,
        fileExtension: _isPdf ? 'pdf' : 'jpg',
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Deposit evidence submitted! Admin has been notified for verification.'),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
      _clearEvidence();
      _loadData();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'verified':
        return AppColors.success;
      case 'submitted_for_verification':
      case 'under_review':
        return AppColors.navy;
      case 'rejected':
        return AppColors.danger;
      case 'expired':
        return AppColors.disabled;
      case 'pending_deposit':
      case 'awaiting_payment':
      default:
        return AppColors.warning;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        title: const Text(
          'Booking Deposit & Bank QR',
          style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Status',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _depositRecord == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'No deposit record found for this auction. Please check back shortly.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 14),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Status Banner
                      _buildStatusCard(),
                      const SizedBox(height: 16),

                      // Admin Custom Instructions Card (when verified)
                      if (_depositRecord!.status == 'verified') ...[
                        _buildAdminVerifiedInstructionsCard(),
                        const SizedBox(height: 16),
                      ],

                      // 2. Countdown Timer (If deposit is pending)
                      if (_depositRecord!.status == 'pending_deposit' || _depositRecord!.status == 'awaiting_payment') ...[
                        CountdownTimerWidget(
                          targetTime: _depositRecord!.paymentDueAt,
                          mode: TimerMode.depositDeadline,
                          onTimerExpired: () => _loadData(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 3. Deposit Breakdown Card
                      _buildBreakdownCard(),
                      const SizedBox(height: 16),

                      // 4. Dynamic Generated QR & Platform Bank Details Card
                      _buildQrAndBankCard(),
                      const SizedBox(height: 16),

                      // 5. Evidence Submission Form (Photo or PDF)
                      if (_depositRecord!.status == 'pending_deposit' ||
                          _depositRecord!.status == 'awaiting_payment' ||
                          _depositRecord!.status == 'rejected') ...[
                        _buildSubmissionForm(),
                        const SizedBox(height: 16),
                      ] else ...[
                        _buildLockedBanner(),
                        const SizedBox(height: 16),
                      ],

                      // 6. Submission History
                      if (_depositRecord!.submissions.isNotEmpty) ...[
                        _buildSubmissionHistory(),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatusCard() {
    final rec = _depositRecord!;
    final color = _getStatusColor(rec.status);

    String title = '10% Booking Deposit Pending';
    String desc = 'Please transfer the 10% booking deposit via Bank Transfer or QR to reserve this vehicle in your name.';

    if (rec.status == 'submitted_for_verification' || rec.status == 'under_review') {
      title = 'Payment Evidence Under Review';
      desc = 'Your payment evidence has been submitted and is currently being verified by the admin team.';
    } else if (rec.status == 'verified') {
      title = 'Deposit Verified • Vehicle Reserved!';
      desc = rec.nextStepInstructions ??
          'Your 10% booking deposit is verified. Visit our showroom to settle the 90% balance and receive full bluebook ownership.';
    } else if (rec.status == 'rejected') {
      title = 'Payment Evidence Rejected';
      desc = 'Admin Reason: ${rec.rejectionReason ?? "Invalid or unreadable receipt"}. Please re-upload clear evidence below.';
    } else if (rec.status == 'expired') {
      title = 'Deposit Deadline Expired';
      desc = 'The 30-minute reservation window has expired.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                rec.status == 'verified'
                    ? Icons.check_circle_rounded
                    : (rec.status == 'rejected' ? Icons.cancel_rounded : Icons.info_outline_rounded),
                color: color,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontFamily: 'Inter', color: color, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 13, height: 1.4),
          ),
          if (rec.status == 'verified') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.directions_car_filled_rounded, color: AppColors.success, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'VEHICLE OFFICIALLY RESERVED IN BUYER\'S NAME',
                      style: TextStyle(fontFamily: 'Inter', color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdminVerifiedInstructionsCard() {
    final instructions = _depositRecord?.nextStepInstructions;
    if (instructions == null || instructions.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mark_email_read_rounded, color: AppColors.success, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Admin Custom Message & Handover Instructions',
                  style: TextStyle(fontFamily: 'Inter', color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Text(
              instructions.trim(),
              style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.secondaryText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Remaining 90% balance due upon physical bluebook handover: Rs. ${_depositRecord!.remainingBalance.toStringAsFixed(0)}',
                  style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    final rec = _depositRecord!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Booking Reference', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13)),
              Row(
                children: [
                  Text(
                    rec.bookingReference,
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _copyToClipboard(rec.bookingReference, 'Booking Reference'),
                    child: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: 20),
          _buildRow('Winning Bid Amount', _currencyFormat.format(rec.winningAmount)),
          const SizedBox(height: 8),
          _buildRow(
            '10% Booking Deposit Due',
            _currencyFormat.format(rec.depositAmount),
            isHighlight: true,
            copyValue: rec.depositAmount.toStringAsFixed(0),
          ),
          const SizedBox(height: 8),
          _buildRow('Remaining 90% at Showroom', _currencyFormat.format(rec.remainingBalance)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Payment Due Deadline (NPT)', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12)),
              Text(
                ServerTimeService.formatNepal(rec.paymentDueAt, pattern: 'hh:mm a, MMM dd', includeTzSuffix: true),
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrAndBankCard() {
    final set = _paymentSettings;
    final rec = _depositRecord!;
    final bankName = set?.bankName ?? 'Global IME Bank Nepal';
    final accName = set?.accountName ?? 'AutoBid Platform Pvt Ltd';
    final accNum = set?.accountNumber ?? '0010100029384';
    final branchName = set?.branchName ?? 'Kathmandu Main Branch';
    final depositAmountStr = rec.depositAmount.toStringAsFixed(0);
    final bookingRef = rec.bookingReference;

    // Structured Nepal Banking payment payload for the dynamic QR code
    final dynamicQrPayload =
        'NEPAL_PAY:bank=$bankName;acc=$accNum;name=$accName;amount=$depositAmountStr;ref=$bookingRef;desc=Auction_10_Percent_Deposit';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_rounded, color: AppColors.navy, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Bank & Payment QR Details',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'NPT Instant Pay',
                  style: TextStyle(fontFamily: 'Inter', color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // QR Code Display with Toggle
          if (_platformQrSignedUrl != null) ...[
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Dynamic QR (with Amount)')),
                    selected: _selectedQrTab == 0,
                    onSelected: (val) => setState(() => _selectedQrTab = 0),
                    selectedColor: AppColors.navy,
                    labelStyle: TextStyle(
                      fontFamily: 'Inter',
                      color: _selectedQrTab == 0 ? Colors.white : AppColors.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Official Bank QR')),
                    selected: _selectedQrTab == 1,
                    onSelected: (val) => setState(() => _selectedQrTab = 1),
                    selectedColor: AppColors.navy,
                    labelStyle: TextStyle(
                      fontFamily: 'Inter',
                      color: _selectedQrTab == 1 ? Colors.white : AppColors.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // QR Visual Container
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (_selectedQrTab == 0 || _platformQrSignedUrl == null) ...[
                    QrImageView(
                      data: dynamicQrPayload,
                      version: QrVersions.auto,
                      size: 200.0,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.navy),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.navy),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Amount: ${_currencyFormat.format(rec.depositAmount)} • Ref: $bookingRef',
                        style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ] else ...[
                    Image.network(_platformQrSignedUrl!, height: 200, width: 200, fit: BoxFit.contain),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Scan with Mobile Banking, eSewa, Khalti, or Fonepay',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Detailed Bank Account Information with Copy Buttons
          _buildCopyableRow('Bank Name', bankName),
          const SizedBox(height: 8),
          _buildCopyableRow('Account Name', accName),
          const SizedBox(height: 8),
          _buildCopyableRow('Account Number', accNum, highlight: true),
          const SizedBox(height: 8),
          _buildCopyableRow('Branch', branchName),
          const SizedBox(height: 8),
          _buildCopyableRow('Transfer Remarks', bookingRef, highlight: true, note: 'Must enter in bank transfer remarks'),
          const SizedBox(height: 8),
          _buildCopyableRow('Deposit Amount Due', _currencyFormat.format(rec.depositAmount), rawCopyText: depositAmountStr),

          if (set?.depositInstructions != null && set!.depositInstructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      set.depositInstructions,
                      style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCopyableRow(String label, String value, {bool highlight = false, String? rawCopyText, String? note}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: highlight ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12)),
              InkWell(
                onTap: () => _copyToClipboard(rawCopyText ?? value, label),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(2.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Copy', style: TextStyle(fontFamily: 'Inter', color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                      SizedBox(width: 4),
                      Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              color: highlight ? AppColors.primary : AppColors.navy,
              fontWeight: FontWeight.bold,
              fontSize: highlight ? 15 : 13,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(note, style: const TextStyle(fontFamily: 'Inter', color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmissionForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.upload_file_rounded, color: AppColors.navy, size: 20),
                SizedBox(width: 8),
                Text(
                  'Upload Payment Evidence (Photo / PDF)',
                  style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Attach your bank deposit voucher, mobile banking screenshot, or PDF statement to send to admin for verification.',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12),
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!, style: const TextStyle(fontFamily: 'Inter', color: AppColors.danger, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Payment Method Selector
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              dropdownColor: AppColors.card,
              style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
              decoration: _buildInputDecoration('Payment Method Used *', Icons.payment_rounded),
              items: const [
                DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer / Mobile Banking')),
                DropdownMenuItem(value: 'qr_payment', child: Text('QR Code / Fonepay Payment')),
                DropdownMenuItem(value: 'connect_ips', child: Text('ConnectIPS Transfer')),
                DropdownMenuItem(value: 'esewa_khalti', child: Text('eSewa / Khalti Wallet')),
                DropdownMenuItem(value: 'receipt_upload', child: Text('Showroom / Cash Deposit Voucher')),
              ],
              onChanged: (val) => setState(() => _paymentMethod = val!),
            ),
            const SizedBox(height: 12),

            // Transaction Reference / UTR
            TextFormField(
              controller: _txnRefController,
              style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
              decoration: _buildInputDecoration('Transaction Reference / UTR / Journal No.', Icons.receipt_long_rounded),
            ),
            const SizedBox(height: 12),

            // Notes / Remarks
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
              decoration: _buildInputDecoration('Optional Notes for Admin Verification', Icons.notes_rounded),
            ),
            const SizedBox(height: 16),

            // Evidence Upload Action Area: Two Options (Photo OR PDF)
            if (_evidenceBytes == null) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.camera_alt_outlined, color: AppColors.primary, size: 18),
                      label: const Text('Upload Photo', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent, size: 18),
                      label: const Text('Upload PDF', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Preview of selected evidence (Photo or PDF)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success, width: 1.5),
                ),
                child: Row(
                  children: [
                    if (_isPdf)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 28),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _evidenceBytes!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _isPdf ? 'PDF DOCUMENT' : 'PHOTO RECEIPT',
                                  style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (_evidenceFileSizeBytes != null)
                                Text(
                                  _formatFileSize(_evidenceFileSizeBytes!),
                                  style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 11),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _evidenceFileName ?? (_isPdf ? 'receipt.pdf' : 'receipt.jpg'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.danger),
                      tooltip: 'Remove',
                      onPressed: _clearEvidence,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSubmitEvidence,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'SEND EVIDENCE TO ADMIN FOR VERIFICATION',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedBanner() {
    final isVerified = _depositRecord!.status == 'verified';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            isVerified ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
            color: isVerified ? AppColors.success : AppColors.navy,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isVerified
                  ? 'Deposit Verified! Vehicle reservation is permanent and ownership handover is underway.'
                  : 'Payment evidence has been received and is currently under admin verification. Editing is locked.',
              style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionHistory() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Submission History',
            style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          ..._depositRecord!.submissions.map((sub) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          sub.evidenceDocPath.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                          size: 16,
                          color: AppColors.navy,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          sub.paymentMethod.toUpperCase().replaceAll('_', ' '),
                          style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      ServerTimeService.formatNepal(sub.createdAt, pattern: 'hh:mm a, MMM dd', includeTzSuffix: true),
                      style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String val, {bool isHighlight = false, String? copyValue}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            color: isHighlight ? AppColors.navy : AppColors.secondaryText,
            fontSize: 13,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Row(
          children: [
            Text(
              val,
              style: TextStyle(
                fontFamily: 'Inter',
                color: isHighlight ? AppColors.primary : AppColors.navy,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                fontSize: isHighlight ? 16 : 13,
              ),
            ),
            if (copyValue != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _copyToClipboard(copyValue, label),
                child: const Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
              ),
            ],
          ],
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.secondaryText, size: 20),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.navy, width: 1.5)),
    );
  }
}
