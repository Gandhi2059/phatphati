// Screen: Winner Deposit & 20-Minute Countdown Panel
// Displays winning summary, 10% deposit calculations, 20-minute countdown timer, and deposit verification.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/widgets/countdown_timer_widget.dart';
import 'package:bid_app/screens/buyer/deposit_details_screen.dart';

class WinnerDepositScreen extends StatefulWidget {
  final Auction auction;
  final AuctionRound round;

  const WinnerDepositScreen({
    super.key,
    required this.auction,
    required this.round,
  });

  @override
  State<WinnerDepositScreen> createState() => _WinnerDepositScreenState();
}

class _WinnerDepositScreenState extends State<WinnerDepositScreen> {
  final AuctionService _service = AuctionService();
  final NumberFormat _currencyFormatter =
      NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);

  bool _isProcessing = false;
  bool _isSecured = false;
  String? _errorMessage;
  DepositRecord? _depositRecord;

  @override
  void initState() {
    super.initState();
    _isSecured = widget.round.status == 'secured';
    _loadDepositRecord();
  }

  Future<void> _loadDepositRecord() async {
    final rec = await _service.fetchDepositRecordForAuction(widget.auction.id);
    if (mounted) {
      setState(() {
        _depositRecord = rec;
        if (rec?.status == 'verified') {
          _isSecured = true;
        }
      });
    }
  }

  Future<void> _handlePayDeposit() async {
    setState(() => _isProcessing = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DepositDetailsScreen(auctionId: widget.auction.id),
        ),
      );
      await _loadDepositRecord();
      final updated = await _service.fetchAuctionDetails(widget.auction.id);
      if (mounted && updated != null) {
        setState(() {
          _isSecured = updated.activeRound?.status == 'secured' || _depositRecord?.status == 'verified';
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final winningBid =
        widget.round.winningBid ?? widget.round.currentHighestBid;
    final depositRequired = widget.round.depositRequired ?? (winningBid * 0.10);
    final deadline = widget.round.depositDeadline ??
        DateTime.now().add(const Duration(minutes: 20));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        title: const Text(
          'Winner & Deposit Summary',
          style: TextStyle(
            fontFamily: 'Inter',
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. CONGRATULATIONS HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isSecured ? AppColors.success : AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isSecured ? AppColors.success : AppColors.border,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    _isSecured ? 'DEPOSIT VERIFIED' : 'AUCTION WINNER',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: _isSecured ? Colors.white : AppColors.navy,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isSecured
                        ? 'Your 10% deposit is verified and your bid is secured.'
                        : 'You won the auction for ${widget.auction.title}!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: _isSecured ? Colors.white : AppColors.secondaryText,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. 20-MINUTE DEPOSIT COUNTDOWN (If not paid yet)
            if (!_isSecured) ...[
              CountdownTimerWidget(
                targetTime: deadline,
                mode: TimerMode.depositDeadline,
                onTimerExpired: () => setState(() {}),
              ),
              const SizedBox(height: 20),
            ],

            // 3. PAYMENT BREAKDOWN CARD
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildDetailRow('AUCTION ITEM', widget.auction.title),
                  const Divider(color: AppColors.border, height: 24),
                  _buildDetailRow(
                      'WINNING BID', _currencyFormatter.format(winningBid),
                      isBold: true),
                  const Divider(color: AppColors.border, height: 24),
                  _buildDetailRow(
                    '10% DEPOSIT REQUIRED',
                    _currencyFormatter.format(depositRequired),
                    valueColor: AppColors.primary,
                    isBold: true,
                  ),
                  const Divider(color: AppColors.border, height: 24),
                  _buildDetailRow(
                    'PAYMENT STATUS',
                    _isSecured ? '10% DEPOSIT VERIFIED' : 'PENDING 10% DEPOSIT',
                    valueColor: _isSecured
                        ? AppColors.success
                        : AppColors.warning,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 4. ACTION BUTTON
            if (!_isSecured)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _handlePayDeposit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_rounded, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'VIEW BANK QR & UPLOAD EVIDENCE',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '10% Deposit Verified • Vehicle Reserved!',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.success,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_depositRecord?.nextStepInstructions != null &&
                        _depositRecord!.nextStepInstructions!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Handover Instructions:',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _depositRecord!.nextStepInstructions!,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.navy,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handlePayDeposit,
                  icon: const Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.navy),
                  label: const Text(
                    'VIEW BOOKING & PAYMENT DETAILS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value,
      {Color valueColor = AppColors.navy, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            color: valueColor,
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

