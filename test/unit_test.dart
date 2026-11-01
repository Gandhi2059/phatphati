// Unit Tests for Auction Models, Roles, and RPC Parameters

import 'package:flutter_test/flutter_test.dart';
import 'package:bid_app/models/auction_models.dart';

void main() {
  group('Profile Model Role Tests', () {
    test('Admin Profile correctly identifies as Admin and non-Buyer', () {
      final profile = Profile(
        id: '11111111-1111-1111-1111-111111111111',
        email: 'admin@auction.com',
        fullName: 'Auction Admin',
        role: 'admin',
      );

      expect(profile.isAdmin, isTrue);
      expect(profile.isBuyer, isFalse);
    });

    test('Buyer Profile correctly parses buyer_id and role', () {
      final json = {
        'id': '22222222-2222-2222-2222-222222222222',
        'buyer_id': 'BUYER-101',
        'email': 'buyer1@auction.com',
        'full_name': 'Alice Smith',
        'role': 'buyer',
      };

      final profile = Profile.fromJson(json);
      expect(profile.buyerId, equals('BUYER-101'));
      expect(profile.isBuyer, isTrue);
      expect(profile.isAdmin, isFalse);
    });
    test('Seller Profile correctly parses role and identifies as Seller', () {
      final json = {
        'id': '33333333-3333-3333-3333-333333333333',
        'email': 'seller@auction.com',
        'full_name': 'Ram Dealer',
        'role': 'seller',
        'account_category': 'dealer',
        'created_at': '2026-10-28T08:00:00.000Z',
      };

      final profile = Profile.fromJson(json);
      expect(profile.isSeller, isTrue);
      expect(profile.isDealer, isTrue);
      expect(profile.isBuyer, isFalse);
      expect(profile.isAdmin, isFalse);
      expect(profile.createdAt, isNotNull);
    });

    test('User without business details is identified as Pending Form 2', () {
      final json = {
        'id': '44444444-4444-4444-4444-444444444444',
        'email': 'unlegit@example.com',
        'full_name': 'Unlegit User',
        'role': 'buyer',
        'account_category': 'recondition',
        'business_status': 'none',
        'business_profile_id': null,
      };

      final profile = Profile.fromJson(json);
      final isPendingForm2 = profile.businessProfileId == null ||
          profile.businessStatus == null ||
          profile.businessStatus == 'none';
      expect(isPendingForm2, isTrue);
    });
  });

  group('Auction & Round Model Serialization', () {
    test('AuctionRound parses status and 10% deposit deadline', () {
      final now = DateTime.now();
      final json = {
        'id': 'r1',
        'auction_id': 'a1',
        'round_number': 1,
        'start_at': now.toIso8601String(),
        'end_at': now.add(const Duration(hours: 1)).toIso8601String(),
        'status': 'winner_pending_deposit',
        'current_highest_bid': 500000.0,
        'winning_bid': 500000.0,
        'deposit_required': 50000.0,
        'deposit_deadline':
            now.add(const Duration(minutes: 20)).toIso8601String(),
      };

      final round = AuctionRound.fromJson(json);
      expect(round.status, equals('winner_pending_deposit'));
      expect(round.winningBid, equals(500000.0));
      expect(round.depositRequired, equals(50000.0));
      expect(round.depositDeadline, isNotNull);
    });
  });
}
