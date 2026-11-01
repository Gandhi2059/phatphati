// Screen: Buyer Auction Detail & Realtime Bidding Panel
// Prominently displays image gallery, live server countdown, current bid, minimum next bid, leader status, and realtime bid history.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/services/app_lifecycle_service.dart';
import 'package:bid_app/widgets/countdown_timer_widget.dart';
import 'package:bid_app/widgets/status_badge_widget.dart';
import 'package:bid_app/screens/buyer/winner_deposit_screen.dart';
import 'package:bid_app/screens/buyer/business_registration_screen.dart';
import 'package:bid_app/screens/admin/admin_create_auction_screen.dart';

class BuyerAuctionDetailScreen extends StatefulWidget {
  final String auctionId;

  const BuyerAuctionDetailScreen({super.key, required this.auctionId});

  @override
  State<BuyerAuctionDetailScreen> createState() =>
      _BuyerAuctionDetailScreenState();
}

class _BuyerAuctionDetailScreenState extends State<BuyerAuctionDetailScreen> {
  final AuctionService _service = AuctionService();
  final NumberFormat _currencyFormatter =
      NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);
  final TextEditingController _bidInputController = TextEditingController();

  Auction? _auction;
  bool _isLoading = true;
  int _currentImageIndex = 0;

  StreamSubscription<AuctionRound>? _roundSubscription;
  StreamSubscription<List<Bid>>? _bidSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAuctionDetails();

    AppLifecycleService().registerResumeCallback(_loadAuctionDetails);

    // Periodic 3-second live sync timer for real-time responsiveness
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadAuctionDetails();
    });

    _roundSubscription = _service.roundStream.listen((round) {
      if (round.auctionId == widget.auctionId && mounted) {
        _loadAuctionDetails();
      }
    });

    _bidSubscription = _service.bidStream.listen((bids) {
      if (mounted) {
        _loadAuctionDetails();
      }
    });

    _profileSubscription = _service.profileStream.listen((_) {
      if (mounted) _loadAuctionDetails();
    });

    _businessSubscription = _service.businessProfileStream.listen((_) {
      if (mounted) _loadAuctionDetails();
    });
  }

  StreamSubscription<Profile>? _profileSubscription;
  StreamSubscription<List<BusinessProfile>>? _businessSubscription;

  @override
  void dispose() {
    AppLifecycleService().removeResumeCallback(_loadAuctionDetails);
    _refreshTimer?.cancel();
    _roundSubscription?.cancel();
    _bidSubscription?.cancel();
    _profileSubscription?.cancel();
    _businessSubscription?.cancel();
    _bidInputController.dispose();
    super.dispose();
  }

  Future<void> _loadAuctionDetails() async {
    try {
      final fresh = await _service.fetchUserProfile(_service.currentUser.id);
      if (fresh != null) _service.setCurrentProfile(fresh);
    } catch (_) {}

    final details = await _service.fetchAuctionDetails(widget.auctionId);
    if (mounted) {
      setState(() {
        _auction = details;
        _isLoading = false;
      });
      _updateBidInput();
    }
  }

  void _updateBidInput([double? customAdd]) {
    if (_auction == null || _auction!.activeRound == null) return;
    final round = _auction!.activeRound!;
    final minNext = round.currentHighestBid == 0
        ? _auction!.startingPrice
        : round.currentHighestBid + _auction!.minIncrement;

    final targetAmount = customAdd != null ? minNext + customAdd : minNext;
    _bidInputController.text = targetAmount.toStringAsFixed(0);
  }

  Future<void> _handlePlaceBid([double? customAmount]) async {
    if (_auction == null) return;
    final round = _auction!.activeRound;
    if (round == null) {
      _showSnackbar('No active bidding round found for this auction.', isError: true);
      return;
    }

    final user = _service.currentUser;
    if (!user.canPlaceBids) {
      _showVerificationRequiredDialog();
      return;
    }

    final double? amount;
    if (customAmount != null) {
      amount = customAmount;
    } else {
      final rawText = _bidInputController.text.replaceAll(',', '').trim();
      amount = double.tryParse(rawText);
    }

    if (amount == null) {
      _showSnackbar('Please enter a valid bid amount.', isError: true);
      return;
    }

    try {
      final res = await _service.placeBid(_auction!.id, amount);

      if (res['success'] == true || res['amount'] != null) {
        _showSnackbar('Bid placed successfully: Rs. ${_currencyFormatter.format(amount)}', isError: false);
        await _loadAuctionDetails();
      }
    } catch (e) {
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      _showSnackbar(errorMsg, isError: true);
    }
  }

  void _showBiddingModalSheet(BuildContext context, double minNextBid, AuctionRound? round) {
    if (!mounted || _auction == null) return;
    final user = _service.currentUser;
    if (!user.canPlaceBids) {
      _showVerificationRequiredDialog();
      return;
    }

    final minIncrement = _auction!.minIncrement;

    final modalController = TextEditingController(
      text: minNextBid.toStringAsFixed(0),
    );
    bool isSubmitting = false;

    // Format increment label smartly (e.g. 5000 → "5k", 10000 → "10k", 100000 → "1L")
    String fmtIncrement(double val) {
      if (val >= 100000) return '${(val / 100000).toStringAsFixed(val % 100000 == 0 ? 0 : 1)}L';
      if (val >= 1000) return '${(val / 1000).toStringAsFixed(val % 1000 == 0 ? 0 : 1)}k';
      return val.toStringAsFixed(0);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final currentParsed =
                double.tryParse(modalController.text.replaceAll(',', '').trim()) ?? minNextBid;

            void setAmount(double newAmount) {
              modalController.text = newAmount.toStringAsFixed(0);
              _bidInputController.text = modalController.text;
              setSheetState(() {});
            }

            void addAmount(double extra) => setAmount(currentParsed + extra);

            // Quick-bid increment options: 1×, 2×, 5× the seller's minIncrement
            final increments = [
              (1 * minIncrement, '+ ${fmtIncrement(1 * minIncrement)}'),
              (2 * minIncrement, '+ ${fmtIncrement(2 * minIncrement)}'),
              (5 * minIncrement, '+ ${fmtIncrement(5 * minIncrement)}'),
            ];

            final isValid = currentParsed >= minNextBid;

            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.gavel_rounded, color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'PLACE YOUR BID',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  Text(
                                    _auction!.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.secondaryText,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.secondaryText),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Min bid info + increment info
                  Row(
                    children: [
                      Expanded(
                        child: _BidInfoTile(
                          label: 'Minimum Bid',
                          value: 'Rs. ${_formatCompact(minNextBid)}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BidInfoTile(
                          label: 'Min Increment',
                          value: 'Rs. ${_formatCompact(minIncrement)}',
                          accent: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Manual bid input
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isValid ? AppColors.primary : AppColors.danger,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: (isValid ? AppColors.primary : AppColors.danger).withValues(alpha: 0.1),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(10),
                              bottomLeft: Radius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Rs.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: isValid ? AppColors.primary : AppColors.danger,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: modalController,
                            keyboardType: TextInputType.number,
                            autofocus: false,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: isValid ? AppColors.navy : AppColors.danger,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              hintText: '0',
                            ),
                            onChanged: (_) => setSheetState(() {}),
                          ),
                        ),
                        // Reset to minimum button
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          color: AppColors.secondaryText,
                          tooltip: 'Reset to minimum',
                          onPressed: () => setAmount(minNextBid),
                        ),
                      ],
                    ),
                  ),

                  if (!isValid) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Minimum bid is Rs. ${_formatCompact(minNextBid)}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Quick-increment buttons (based on seller's minIncrement)
                  Row(
                    children: [
                      // "Minimum bid" quick button
                      Expanded(
                        child: _QuickBidButton(
                          label: 'Min Bid',
                          sublabel: 'Rs. ${_formatCompact(minNextBid)}',
                          isHighlighted: true,
                          onTap: () => setAmount(minNextBid),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Increment buttons
                      ...increments.map((inc) => [
                        Expanded(
                          child: _QuickBidButton(
                            label: inc.$2,
                            sublabel: 'Rs. ${_formatCompact(currentParsed + inc.$1)}',
                            onTap: () => addAmount(inc.$1),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ]).expand((w) => w).toList()
                        ..removeLast(),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (isSubmitting || !isValid)
                          ? null
                          : () async {
                              final amt = double.tryParse(
                                  modalController.text.replaceAll(',', '').trim());
                              if (amt == null || amt < minNextBid) {
                                _showSnackbar(
                                    'Bid must be at least Rs. ${_formatCompact(minNextBid)}',
                                    isError: true);
                                return;
                              }
                              setSheetState(() => isSubmitting = true);
                              Navigator.pop(sheetContext);
                              await _handlePlaceBid(amt);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.gavel_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  isValid
                                      ? 'CONFIRM BID — Rs. ${_formatCompact(currentParsed)}'
                                      : 'CONFIRM & PLACE BID',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatCompact(double val) {
    if (val >= 100000) {
      final l = val / 100000;
      return '${l % 1 == 0 ? l.toInt() : l.toStringAsFixed(1)}L';
    }
    if (val >= 1000) {
      final k = val / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return val.toStringAsFixed(0);
  }



  void _showVerificationRequiredDialog() {
    final status = _service.currentUser.businessStatus;
    String title = 'Business Verification Required';
    String message = 'To participate in bidding, Form 2 (Business Verification & Documentation) must be submitted and approved by an Admin.';
    String actionLabel = 'Complete Form 2';
    Color iconColor = AppColors.primary;
    IconData icon = Icons.verified_user_outlined;

    if (status == 'pending') {
      title = 'Verification Pending';
      message = 'Your Form 2 (Business Verification) is currently awaiting Admin approval. Bidding will be unlocked once an Admin approves your account.';
      actionLabel = 'View Submission';
      iconColor = AppColors.amber;
      icon = Icons.hourglass_top_rounded;
    } else if (status == 'rejected') {
      title = 'Verification Rejected';
      message = 'Your Business Verification was rejected by Admin. Please update and resubmit your documentation to enable bidding.';
      actionLabel = 'Update Form 2';
      iconColor = AppColors.danger;
      icon = Icons.error_outline_rounded;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.navy,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: AppColors.secondaryText,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.secondaryText)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
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
              _loadAuctionDetails();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBiddingVerificationBanner() {
    final user = _service.currentUser;
    if (user.isAdmin || user.canPlaceBids || user.businessStatus == 'approved') {
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
        ? 'Verification Rejected'
        : (isPending ? 'Verification Pending Approval' : 'Business Verification Required');

    final actionLabel = isRejected ? 'Fix Form 2' : (isPending ? 'View Form 2' : 'Complete Form 2');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$title: Form 2 must be approved by Admin before placing bids.',
              style: TextStyle(
                fontFamily: 'Inter',
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _showVerificationRequiredDialog,
            child: Text(
              actionLabel,
              style: TextStyle(
                fontFamily: 'Inter',
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor:
            isError ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
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
      await _service.deleteAuction(auction.id);
      if (mounted) {
        _showSnackbar('Auction and bids deleted successfully.');
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.navy, elevation: 0),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_auction == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Auction Details')),
        body: const Center(
          child: Text(
            'Auction not found',
            style: TextStyle(fontFamily: 'Inter', color: AppColors.navy),
          ),
        ),
      );
    }

    final round = _auction!.activeRound;
    final isWinner = round?.highestBidderId == _service.currentUser.id &&
        (round?.status == 'winner_pending_deposit' ||
            round?.status == 'secured');

    if (isWinner && round?.status == 'winner_pending_deposit') {
      return WinnerDepositScreen(auction: _auction!, round: round!);
    }

    final isLeading = round?.highestBidderId == _service.currentUser.id;
    final effectiveStatus = round?.effectiveStatus ?? _auction!.effectiveStatus;
    final isLive = effectiveStatus == 'live';
    final isUpcoming = effectiveStatus == 'upcoming';
    final isCompleted = _auction!.isCompleted ||
        effectiveStatus == 'ended' ||
        effectiveStatus == 'secured' ||
        effectiveStatus == 'finalised' ||
        effectiveStatus == 'expired';
    final user = _service.currentUser;
    final isAdmin = user.isAdmin;
    final canManageAuction = user.isAdmin || user.isSeller || user.isDealer || _auction!.createdBy == user.id;

    final double highestBid = round?.currentHighestBid ?? 0;
    final bool hasBidsPlaced = highestBid > 0;
    final minNextBid = !hasBidsPlaced
        ? _auction!.startingPrice
        : highestBid + _auction!.minIncrement;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        title: Text(
          _auction!.title,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          if (canManageAuction) ...[
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
              tooltip: 'Edit Vehicle Auction',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminCreateAuctionScreen(auction: _auction),
                  ),
                );
                _loadAuctionDetails();
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              tooltip: 'Delete Auction & Bids',
              onPressed: () => _handleDeleteAuction(_auction!),
            ),
          ],
        ],
      ),

      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. IMAGE GALLERY CAROUSEL
            Builder(
              builder: (context) {
                final galleryPhotos = _getGalleryPhotos();
                return Stack(
                  children: [
                    SizedBox(
                      height: 240,
                      child: PageView.builder(
                        itemCount: galleryPhotos.length,
                        onPageChanged: (index) =>
                            setState(() => _currentImageIndex = index),
                        itemBuilder: (context, index) {
                          final url = galleryPhotos[index];
                          return GestureDetector(
                            onTap: () => _showFullScreenImage(
                                context, url, 'Vehicle Photo ${index + 1}'),
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.background,
                                child: const Icon(Icons.two_wheeler,
                                    color: AppColors.secondaryText, size: 64),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: StatusBadgeWidget(
                        status: round?.status ?? _auction!.status,
                        isLeading: isLeading,
                      ),
                    ),
                    if (galleryPhotos.length > 1)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_currentImageIndex + 1} / ${galleryPhotos.length}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TITLE & DESCRIPTION
                  Text(
                    _auction!.title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.navy,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_auction!.isBusinessAuction) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_rounded, color: AppColors.success, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Verified Business Seller${_auction!.businessBrand != null ? " (${_auction!.businessBrand})" : ""}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // 2. VEHICLE SPECIFICATIONS CARD
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'VEHICLE SPECIFICATIONS',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppColors.navy,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                '${_auction!.vehicleType} • ${_auction!.fuelType}',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppColors.navy,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: AppColors.border, height: 24),
                        Row(
                          children: [
                            Expanded(child: _buildSpecTile('Brand', _auction!.brandName)),
                            Expanded(child: _buildSpecTile('Model', _auction!.model)),
                            Expanded(child: _buildSpecTile('Year', '${_auction!.builtYear} ${_auction!.yearCalendar}')),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: _buildSpecTile('Lot No.', _auction!.lotNumber)),
                            Expanded(child: _buildSpecTile('Reg. No.', _auction!.registrationNumber)),
                            Expanded(child: _buildSpecTile('KM Run', '${_auction!.kilometresRun.toStringAsFixed(0)} KM')),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: _buildSpecTile('Owners', '${_auction!.numberOfOwners} Owner(s)')),
                            Expanded(child: _buildSpecTile('Colour', _auction!.colour)),
                            Expanded(child: _buildSpecTile('Tax Status', _auction!.taxStatus)),
                          ],
                        ),
                        if (_auction!.fuelType == 'Petrol') ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(child: _buildSpecTile('Engine Opened', _auction!.engineOpened ?? 'N/A')),
                              Expanded(child: _buildSpecTile('Engine Capacity', _auction!.engineCapacity != null ? '${_auction!.engineCapacity!.toStringAsFixed(0)} CC' : 'N/A')),
                              const Expanded(child: SizedBox()),
                            ],
                          ),
                        ] else if (_auction!.fuelType == 'EV') ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(child: _buildSpecTile('Motor Type', 'Electric Motor')),
                              Expanded(child: _buildSpecTile('Battery Tech', 'Lithium-Ion')),
                              Expanded(child: _buildSpecTile('Emissions', 'Zero (EV)')),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. PRIVATE BLUE BOOK DOCUMENTS SECTION
                  _buildPrivateBlueBookSection(),
                  const SizedBox(height: 16),

                  // 4. LIVE COUNTDOWN TIMER
                  if (round != null) ...[
                    CountdownTimerWidget(
                      key: ValueKey('detail_timer_${_auction!.id}_${round.id}_${isUpcoming ? "up" : "live"}'),
                      targetTime: isUpcoming ? round.startAt : round.endAt,
                      mode: isUpcoming ? TimerMode.startsIn : TimerMode.endsIn,
                      onTimerExpired: () => _loadAuctionDetails(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 5. CURRENT BID & NEXT MINIMUM BID CARD
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isLeading ? AppColors.success : AppColors.border,
                        width: isLeading ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasBidsPlaced ? 'CURRENT HIGHEST BID' : 'STARTING PRICE',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.secondaryText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currencyFormatter.format(
                                      hasBidsPlaced ? highestBid : _auction!.startingPrice),
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.navy,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'MINIMUM NEXT BID',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currencyFormatter.format(minNextBid),
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.primary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(color: AppColors.border, height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'YOUR STATUS:',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.secondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isLeading ? 'HIGHEST BIDDER' : 'NOT LEADING',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: isLeading
                                    ? AppColors.success
                                    : AppColors.secondaryText,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),


                  // 4. BIDDING CONTROLS & ACTIVE BID EDITING (Only for LIVE auctions)
                  if (isLive) ...[
                    FutureBuilder<List<Bid>>(
                      future: _service.fetchBidsForRound(round?.id ?? ''),
                      builder: (context, snapshot) {
                        final bidsList = snapshot.data ?? [];
                        final myBids = bidsList.where((b) => b.bidderId == _service.currentUser.id).toList();
                        final myHighestBid = myBids.isNotEmpty ? myBids.first : null;
                        final hasBidded = myHighestBid != null;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasBidded) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: isLeading
                                      ? AppColors.success.withValues(alpha: 0.08)
                                      : AppColors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isLeading ? AppColors.success : AppColors.amber,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'YOUR CURRENT ACTIVE BID',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            color: AppColors.secondaryText,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _currencyFormatter.format(myHighestBid.amount),
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            color: AppColors.navy,
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isLeading ? AppColors.success : AppColors.amber,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        isLeading ? 'YOU ARE LEADING' : 'OUTBID • REVISE BID',
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            Text(
                              hasBidded ? 'REVISE / INCREASE YOUR BID' : 'PLACE YOUR BID',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.navy,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Quick Add Chips
                            _buildBiddingVerificationBanner(),
                            Row(
                              children: [
                                _buildQuickAddChip('+ Rs. 5,000', 5000),
                                const SizedBox(width: 8),
                                _buildQuickAddChip('+ Rs. 10,000', 10000),
                                const SizedBox(width: 8),
                                _buildQuickAddChip('+ Rs. 25,000', 25000),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Custom Amount Input & Submit Action
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: AppColors.card,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.border, width: 1.5),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.08),
                                            borderRadius: const BorderRadius.only(
                                              topLeft: Radius.circular(8),
                                              bottomLeft: Radius.circular(8),
                                            ),
                                          ),
                                          child: const Text(
                                            'Rs.',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              color: AppColors.primary,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: _bidInputController,
                                            keyboardType: TextInputType.number,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              color: AppColors.navy,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                              hintText: 'Enter bid amount',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: _handlePlaceBid,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(120, 52),
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      hasBidded ? 'REVISE BID' : 'PLACE BID',
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ] else if (isUpcoming) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Auction starts soon. You can pre-bid or bid as soon as the countdown starts.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.secondaryText,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => _showBiddingModalSheet(context, minNextBid, round),
                            icon: const Icon(Icons.gavel_rounded, size: 16),
                            label: const Text('PREPARE / PLACE BID'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 5. LIVE BID HISTORY & BIDDER TRANSPARENCY
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'REALTIME BID HISTORY',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isAdmin && round != null)
                        TextButton.icon(
                          onPressed: () => _showBidderRosterSheet(round.id),
                          icon: const Icon(Icons.people_alt_outlined, size: 16, color: AppColors.primary),
                          label: const Text(
                            'Bidder Roster',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (round != null)
                    FutureBuilder<List<Bid>>(
                      future: _service.fetchBidsForRound(round.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(color: AppColors.primary),
                          );
                        }
                        final bidsList = snapshot.data ?? [];
                        if (bidsList.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No bids placed yet. Be the first to bid!',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.secondaryText,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: bidsList.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final b = bidsList[index];
                            final isTop = index == 0;
                            final isMe = b.bidderId == _service.currentUser.id;
                            
                            // Anonymize buyer identity for public buyers; reserve detailed names/IDs for authorized admin
                            final String displayLabel = isAdmin
                                ? '${b.bidderProfile?.fullName ?? "Buyer"} (${b.bidderProfile?.buyerId ?? "BUYER-ID"})'
                                : (isMe ? 'YOU' : 'Verified Bidder #${bidsList.length - index}');

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isTop
                                    ? AppColors.success.withValues(alpha: 0.08)
                                    : AppColors.card,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isTop ? AppColors.success : AppColors.border,
                                  width: isTop ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (isTop) ...[
                                              const Icon(Icons.stars_rounded, color: AppColors.success, size: 16),
                                              const SizedBox(width: 4),
                                            ],
                                            Flexible(
                                              child: Text(
                                                displayLabel,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontFamily: 'Inter',
                                                  color: isTop ? AppColors.success : AppColors.navy,
                                                  fontWeight: isTop ? FontWeight.bold : FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.navy,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'YOU',
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Time: ${ServerTimeService.formatNepalTime(b.createdAt, showSeconds: true, includeTzSuffix: true)}',
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            color: AppColors.secondaryText,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _currencyFormatter.format(b.amount),
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: isTop ? AppColors.success : AppColors.navy,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isCompleted
          ? null
          : BottomAppBar(
              color: AppColors.card,
              elevation: 8,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              height: 72,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isLive && hasBidsPlaced ? 'MIN NEXT BID' : 'STARTING PRICE',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.secondaryText,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _currencyFormatter.format(isLive ? minNextBid : _auction!.startingPrice),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.primary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      _showBiddingModalSheet(context, minNextBid, round);
                    },
                    icon: const Icon(Icons.gavel_rounded, size: 18, color: Colors.white),
                    label: Text(
                      isLive ? 'PLACE BID' : (isUpcoming ? 'BID NOW' : 'PLACE BID'),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(130, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showBidderRosterSheet(String roundId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'AUCTION BIDDER DIRECTORY',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.navy,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.navy),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Bid>>(
                  future: _service.fetchBidsForRound(roundId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                    }
                    final bids = snapshot.data!;
                    if (bids.isEmpty) {
                      return const Center(
                        child: Text('No bidders found for this round.', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
                      );
                    }
                    return ListView.separated(
                      itemCount: bids.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.border),
                      itemBuilder: (context, index) {
                        final b = bids[index];
                        final p = b.bidderProfile;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                            child: Text(
                              (p?.fullName ?? 'B').substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            '${p?.fullName ?? "Buyer"} (${p?.buyerId ?? "BUYER-ID"})',
                            style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            'Email: ${p?.email ?? "N/A"} | Category: ${p?.accountCategory ?? "individual"}\nPlaced Bid: ${_currencyFormatter.format(b.amount)}',
                            style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: index == 0 ? AppColors.success.withValues(alpha: 0.1) : AppColors.background,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              index == 0 ? 'HIGHEST' : '#${index + 1}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: index == 0 ? AppColors.success : AppColors.secondaryText,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickAddChip(String label, double addAmount) {
    return Expanded(
      child: InkWell(
        onTap: () => _updateBidInput(addAmount),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.secondaryText,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.navy,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  List<String> _getGalleryPhotos() {
    if (_auction == null) return [];
    final photos = <String>[];
    for (final img in _auction!.images) {
      if (img.imageUrl.isNotEmpty) photos.add(img.imageUrl);
    }
    for (final p in [
      _auction!.vehicleFrontPath,
      _auction!.vehicleBackPath,
      _auction!.vehicleRightPath,
      _auction!.vehicleLeftPath,
    ]) {
      if (p != null && p.isNotEmpty && !photos.contains(p)) {
        photos.add(p);
      }
    }
    if (photos.isEmpty) {
      photos.add(_auction!.primaryImageUrl);
    }
    return photos;
  }

  Widget _buildPrivateBlueBookSection() {
    final docs = <Map<String, String>>[
      if (_auction!.bluebookFrontPath != null && _auction!.bluebookFrontPath!.isNotEmpty)
        {'label': 'Blue Book Front', 'path': _auction!.bluebookFrontPath!},
      if (_auction!.bluebookBackPath != null && _auction!.bluebookBackPath!.isNotEmpty)
        {'label': 'Blue Book Back', 'path': _auction!.bluebookBackPath!},
      if (_auction!.bluebookOwnerPath != null && _auction!.bluebookOwnerPath!.isNotEmpty)
        {'label': 'Blue Book Owner', 'path': _auction!.bluebookOwnerPath!},
      if (_auction!.odometerPath != null && _auction!.odometerPath!.isNotEmpty)
        {'label': 'Odometer Reading', 'path': _auction!.odometerPath!},
      if (_auction!.vehicleFrontPath != null && _auction!.vehicleFrontPath!.isNotEmpty)
        {'label': 'Vehicle Front', 'path': _auction!.vehicleFrontPath!},
      if (_auction!.vehicleBackPath != null && _auction!.vehicleBackPath!.isNotEmpty)
        {'label': 'Vehicle Rear', 'path': _auction!.vehicleBackPath!},
      if (_auction!.vehicleRightPath != null && _auction!.vehicleRightPath!.isNotEmpty)
        {'label': 'Vehicle Right', 'path': _auction!.vehicleRightPath!},
      if (_auction!.vehicleLeftPath != null && _auction!.vehicleLeftPath!.isNotEmpty)
        {'label': 'Vehicle Left', 'path': _auction!.vehicleLeftPath!},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'VERIFICATION DOCUMENTS',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PUBLIC VERIFIED',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: 20),
          const Text(
            'Tap any uploaded document or photo below to view in full screen:',
            style: TextStyle(
              fontFamily: 'Inter',
              color: AppColors.secondaryText,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          if (docs.isEmpty)
            Row(
              children: [
                Expanded(child: _buildPrivateDocTile('Front', _auction!.bluebookFrontPath)),
                const SizedBox(width: 8),
                Expanded(child: _buildPrivateDocTile('Back', _auction!.bluebookBackPath)),
                const SizedBox(width: 8),
                Expanded(child: _buildPrivateDocTile('Owner', _auction!.bluebookOwnerPath)),
              ],
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final d = docs[index];
                return _buildPrivateDocTile(d['label']!, d['path']);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPrivateDocTile(String label, String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        height: 90,
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
        child: Center(
          child: Text('No $label', style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 11)),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: _service.getPrivateDocumentSignedUrl(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 90,
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
            child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        final signedUrl = snapshot.data;
        if (signedUrl == null) {
          return Container(
            height: 90,
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
            child: Center(
              child: Text('$label\nUnavailable', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Inter', color: AppColors.danger, fontSize: 11)),
            ),
          );
        }

        return GestureDetector(
          onTap: () => _showFullScreenImage(context, signedUrl, label),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    child: Image.network(
                      signedUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.background,
                        child: const Icon(Icons.broken_image_rounded, color: AppColors.secondaryText, size: 24),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.navy,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFullScreenImage(BuildContext context, String url, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      'Failed to load document image',
                      style: TextStyle(color: Colors.white, fontFamily: 'Inter'),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BidInfoTile extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;

  const _BidInfoTile({
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: accent ? AppColors.primary : AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickBidButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _QuickBidButton({
    required this.label,
    required this.sublabel,
    this.isHighlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isHighlighted
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted ? AppColors.primary : AppColors.border,
              width: isHighlighted ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isHighlighted ? AppColors.primary : AppColors.navy,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  color: AppColors.secondaryText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

