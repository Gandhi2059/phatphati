// Screen: In-App Notification Center
// Displays categorized notifications, unread badges, mark as read, and direct navigation to auctions.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/screens/buyer/buyer_auction_detail_screen.dart';
import 'package:bid_app/screens/admin/admin_buyer_management_screen.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final AuctionService _service = AuctionService();
  StreamSubscription<List<NotificationModel>>? _subscription;
  List<NotificationModel> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscription = _service.notificationStream.listen((list) {
      if (mounted) {
        setState(() => _notifications = list);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    final list = await _service.fetchNotificationsForUser();
    if (mounted) {
      setState(() {
        _notifications = list;
      });
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
          'Notifications',
          style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
      ),
      body: _notifications.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_outlined,
                      color: AppColors.secondaryText, size: 56),
                  SizedBox(height: 12),
                  Text(
                    'No notifications yet',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.secondaryText,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final n = _notifications[index];
                return InkWell(
                  onTap: () {
                    _service.markNotificationRead(n.id);
                    if (n.type == 'form1_registration' || n.entityType == 'user_profile') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminBuyerManagementScreen(),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BuyerAuctionDetailScreen(auctionId: n.entityId)),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: n.isRead
                          ? AppColors.cardBackground
                          : AppColors.amber.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: n.isRead
                            ? AppColors.border
                            : AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _getNotificationIcon(n.type),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      n.title,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    ServerTimeService.formatNepalTime(n.createdAt, includeTzSuffix: true),
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.secondaryText,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                n.message,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppColors.secondaryText,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _getNotificationIcon(String type) {
    IconData iconData = Icons.notifications_outlined;
    Color iconColor = AppColors.navy;

    switch (type) {
      case 'form1_registration':
      case 'user_registration':
        iconData = Icons.person_add_alt_1_rounded;
        iconColor = AppColors.primary;
        break;
      case 'leading_bid':
        iconData = Icons.emoji_events_outlined;
        iconColor = AppColors.success;
        break;
      case 'outbid':
        iconData = Icons.gavel_outlined;
        iconColor = AppColors.danger;
        break;
      case 'auction_won':
      case 'deposit_required':
        iconData = Icons.card_giftcard_outlined;
        iconColor = AppColors.amber;
        break;
      case 'deposit_paid':
        iconData = Icons.verified_outlined;
        iconColor = AppColors.success;
        break;
      case 'deposit_expired':
        iconData = Icons.error_outline_rounded;
        iconColor = AppColors.danger;
        break;
      case 'auction_reopened':
        iconData = Icons.autorenew_rounded;
        iconColor = AppColors.primary;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: iconColor, size: 20),
    );
  }
}
