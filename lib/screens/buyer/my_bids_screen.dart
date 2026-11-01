// Buyer My Bids Screen: Displays Real Bids placed by logged-in buyer

import 'package:flutter/material.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/screens/buyer/buyer_auction_detail_screen.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/services/server_time_service.dart';

class MyBidsScreen extends StatefulWidget {
  const MyBidsScreen({super.key});

  @override
  State<MyBidsScreen> createState() => _MyBidsScreenState();
}

class _MyBidsScreenState extends State<MyBidsScreen> {
  final AuctionService _service = AuctionService();
  List<Bid> _bids = [];
  Map<String, Auction> _auctionMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBuyerBids();
  }

  Future<void> _loadBuyerBids() async {
    setState(() => _isLoading = true);
    final buyerId = _service.currentUser.id;
    final bids = await _service.fetchBuyerBids(buyerId);
    final auctions = await _service.fetchAuctions();
    final map = <String, Auction>{};
    for (final a in auctions) {
      map[a.id] = a;
    }

    if (mounted) {
      setState(() {
        _bids = bids;
        _auctionMap = map;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDeleteBid(String bidId) async {
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
              'Delete Bid Entry',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this bid entry from your history?',
          style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
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
      await _service.deleteSingleBid(bidId);
      await _loadBuyerBids();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        title: const Text(
          'My Placed Bids',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBuyerBids,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _bids.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.gavel_outlined, size: 56, color: AppColors.secondaryText),
                      SizedBox(height: 16),
                      Text(
                        'No bids placed yet',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.navy,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Explore live auctions and place your first bid.',
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
                  itemCount: _bids.length,
                  itemBuilder: (context, index) {
                    final bid = _bids[index];
                    final auction = _auctionMap[bid.auctionId];
                    final isLeading = auction?.activeRound?.highestBidderId ==
                        _service.currentUser.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isLeading ? AppColors.success : AppColors.border,
                          width: isLeading ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            image: auction != null
                                ? DecorationImage(
                                    image: NetworkImage(auction.primaryImageUrl),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: auction == null
                              ? const Icon(Icons.two_wheeler, color: AppColors.secondaryText)
                              : null,
                        ),
                        title: Text(
                          auction?.title ??
                              'Auction #${bid.auctionId.substring(0, 8)}',
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Text(
                                  'My Bid: ',
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.secondaryText,
                                      fontSize: 13),
                                ),
                                Text(
                                  'Rs. ${bid.amount.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              ServerTimeService.formatNepal(bid.createdAt, pattern: 'MMM d, h:mm:ss a'),
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppColors.secondaryText,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: isLeading
                                    ? AppColors.success.withValues(alpha: 0.1)
                                    : AppColors.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isLeading ? AppColors.success : AppColors.danger,
                                ),
                              ),
                              child: Text(
                                isLeading ? 'HIGHEST' : 'OUTBID',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: isLeading ? AppColors.success : AppColors.danger,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 18),
                              tooltip: 'Delete Bid Record',
                              onPressed: () => _handleDeleteBid(bid.id),
                            ),
                          ],
                        ),
                        onTap: auction == null
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BuyerAuctionDetailScreen(
                                        auctionId: auction.id),
                                  ),
                                );
                              },
                      ),
                    );
                  },
                ),
    );
  }
}

