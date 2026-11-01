// Buyer Won Auctions Screen: Real Won Auctions & 10% Deposit Management

import 'package:flutter/material.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/screens/buyer/deposit_details_screen.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/widgets/countdown_timer_widget.dart';

class WonAuctionsScreen extends StatefulWidget {
  const WonAuctionsScreen({super.key});

  @override
  State<WonAuctionsScreen> createState() => _WonAuctionsScreenState();
}

class _WonAuctionsScreenState extends State<WonAuctionsScreen> {
  final AuctionService _service = AuctionService();
  List<AuctionRound> _wonRounds = [];
  Map<String, Auction> _auctionMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWonAuctions();
  }

  Future<void> _loadWonAuctions() async {
    setState(() => _isLoading = true);
    final buyerId = _service.currentUser.id;
    final rounds = await _service.fetchBuyerWins(buyerId);
    final auctions = await _service.fetchAuctions();
    final map = <String, Auction>{};
    for (final a in auctions) {
      map[a.id] = a;
    }

    if (mounted) {
      setState(() {
        _wonRounds = rounds;
        _auctionMap = map;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        title: const Text(
          'Won Auctions & Deposits',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadWonAuctions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _wonRounds.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.emoji_events_outlined, size: 56, color: AppColors.secondaryText),
                      SizedBox(height: 16),
                      Text(
                        'No won auctions yet',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.navy,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Win auctions to secure your items with a 10% deposit.',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.secondaryText,
                            fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _wonRounds.length,
                  itemBuilder: (context, index) {
                    final round = _wonRounds[index];
                    final auction = _auctionMap[round.auctionId];
                    final isSecured = round.status == 'secured';
                    final depositAmount = round.depositRequired ??
                        ((round.winningBid ?? round.currentHighestBid) * 0.10);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSecured ? AppColors.success : AppColors.warning,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(8),
                                  image: auction != null
                                      ? DecorationImage(
                                          image: NetworkImage(
                                              auction.primaryImageUrl),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: auction == null
                                    ? const Icon(Icons.two_wheeler,
                                        color: AppColors.secondaryText)
                                    : null,
                               ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      auction?.title ?? 'Auction Item',
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Winning Bid: Rs. ${(round.winningBid ?? round.currentHighestBid).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: AppColors.border, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '10% Deposit Due',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.secondaryText,
                                        fontSize: 12),
                                  ),
                                  Text(
                                    'Rs. ${depositAmount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              if (!isSecured && round.depositDeadline != null)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text(
                                      'Deposit Deadline',
                                      style: TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.danger,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    CountdownTimerWidget(
                                      targetTime: round.depositDeadline!,
                                      mode: TimerMode.depositDeadline,
                                      compact: true,
                                      onTimerExpired: () => _loadWonAuctions(),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (auction != null)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final res = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DepositDetailsScreen(
                                        auctionId: auction.id,
                                      ),
                                    ),
                                  );
                                  if (res == true) _loadWonAuctions();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSecured
                                      ? AppColors.success
                                      : AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text(
                                  isSecured
                                      ? '10% DEPOSIT VERIFIED'
                                      : 'PAY 10% DEPOSIT & UPLOAD RECEIPT',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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

