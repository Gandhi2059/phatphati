// Widget: Visual Status Badges for Auctions & Leader States
// Restrained Automotive Design System

import 'package:flutter/material.dart';
import 'package:bid_app/theme/app_theme.dart';


class StatusBadgeWidget extends StatelessWidget {
  final String status;
  final bool isLeading;

  const StatusBadgeWidget({
    super.key,
    required this.status,
    this.isLeading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLeading) {
      return _buildBadge(
        label: 'HIGHEST BIDDER',
        bgColor: const Color(0xFFE6F4EA),
        textColor: AppColors.success,
        borderColor: AppColors.success,
      );
    }

    switch (status.toLowerCase()) {
      case 'live':
        return _buildBadge(
          label: 'LIVE AUCTION',
          bgColor: const Color(0xFFFEE4E2),
          textColor: AppColors.danger,
          borderColor: AppColors.danger,
        );
      case 'upcoming':
        return _buildBadge(
          label: 'UPCOMING',
          bgColor: const Color(0xFFFEF3C7),
          textColor: AppColors.warning,
          borderColor: AppColors.warning,
        );
      case 'winner_pending_deposit':
        return _buildBadge(
          label: 'PENDING 10% DEPOSIT',
          bgColor: const Color(0xFFFEF3C7),
          textColor: AppColors.warning,
          borderColor: AppColors.warning,
        );
      case 'under_review':
        return _buildBadge(
          label: 'UNDER REVIEW',
          bgColor: const Color(0xFFFEF3C7),
          textColor: AppColors.warning,
          borderColor: AppColors.warning,
        );
      case 'secured':
      case 'deposit_verified':
      case 'verified':
        return _buildBadge(
          label: '10% DEPOSIT VERIFIED',
          bgColor: const Color(0xFFE6F4EA),
          textColor: AppColors.success,
          borderColor: AppColors.success,
        );
      case 'approved':
        return _buildBadge(
          label: 'APPROVED',
          bgColor: const Color(0xFFE6F4EA),
          textColor: AppColors.success,
          borderColor: AppColors.success,
        );
      case 'rejected':
        return _buildBadge(
          label: 'REJECTED',
          bgColor: const Color(0xFFFEE4E2),
          textColor: AppColors.danger,
          borderColor: AppColors.danger,
        );
      case 'expired':
        return _buildBadge(
          label: 'EXPIRED',
          bgColor: AppColors.background,
          textColor: AppColors.secondaryText,
          borderColor: AppColors.border,
        );
      default:
        return _buildBadge(
          label: status.replaceAll('_', ' ').toUpperCase(),
          bgColor: AppColors.background,
          textColor: AppColors.secondaryText,
          borderColor: AppColors.border,
        );
    }
  }

  Widget _buildBadge({
    required String label,
    required Color bgColor,
    required Color textColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

