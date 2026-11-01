// Models for Auction Application

import 'package:bid_app/services/server_time_service.dart';

class Profile {
  final String id;
  final String? buyerId; // Admin-generated Buyer ID (e.g. BUYER-101)
  final String email;
  final String fullName;
  final String? phone;
  final String role; // 'admin' or 'buyer'
  final String? avatarUrl;

  final String? accountCategory; // 'individual', 'dealer', 'recondition'
  final String? businessProfileId;
  final String? businessStatus; // 'none', 'pending', 'approved', 'rejected', 'suspended'
  final String? businessType;
  final bool emailVerified;
  final bool phoneVerified;
  final DateTime? phoneVerifiedAt;
  final DateTime? createdAt;

  Profile({
    required this.id,
    this.buyerId,
    required this.email,
    required this.fullName,
    this.phone,
    required this.role,
    this.avatarUrl,
    this.accountCategory,
    this.businessProfileId,
    this.businessStatus,
    this.businessType,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.phoneVerifiedAt,
    this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] ?? '',
      buyerId: json['buyer_id'] ?? json['buyerId'],
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? json['fullName'] ?? 'User',
      phone: json['phone'],
      role: json['role'] ?? 'buyer',
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
      accountCategory: json['account_category'] ?? json['accountCategory'] ?? 'individual',
      businessProfileId: json['business_profile_id'] ?? json['businessProfileId'],
      businessStatus: json['business_status'] ?? json['businessStatus'] ?? 'none',
      businessType: json['business_type'] ?? json['businessType'],
      emailVerified: json['email_verified'] == true || json['email_confirmed_at'] != null,
      phoneVerified: json['phone_verified'] == true,
      phoneVerifiedAt: json['phone_verified_at'] != null ? DateTime.tryParse(json['phone_verified_at'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isSeller => role == 'seller' || role == 'dealer' || accountCategory == 'dealer';
  bool get isBuyer => (role == 'buyer' || accountCategory == 'recondition') && accountCategory != 'dealer';
  bool get isDealer => accountCategory == 'dealer' || role == 'dealer' || role == 'seller';
  bool get isReconditioner => accountCategory == 'recondition' || (isBuyer && accountCategory != 'dealer');
  bool get isApprovedBusiness => isAdmin || businessStatus == 'approved' || isSeller || isDealer || isReconditioner;
  bool get canCreateAuctions => isAdmin || isSeller || isDealer;
  bool get canPlaceBids => isAdmin || businessStatus == 'approved' || isBuyer || isReconditioner;
  bool get isBusiness => isDealer || isReconditioner || isSeller;
}

class AuctionImage {
  final String id;
  final String auctionId;
  final String imageUrl;
  final int displayOrder;
  final bool isCover;

  AuctionImage({
    required this.id,
    required this.auctionId,
    required this.imageUrl,
    required this.displayOrder,
    required this.isCover,
  });

  factory AuctionImage.fromJson(Map<String, dynamic> json) {
    return AuctionImage(
      id: json['id'] ?? '',
      auctionId: json['auction_id'] ?? '',
      imageUrl: json['image_url'] ??
          'https://images.unsplash.com/photo-1549399542-7e3f8b79c341?w=800',
      displayOrder: json['display_order'] ?? 0,
      isCover: json['is_cover'] ?? false,
    );
  }
}

class AuctionRound {
  final String id;
  final String auctionId;
  final int roundNumber;
  final DateTime startAt;
  final DateTime endAt;
  final String
      status; // 'upcoming' | 'live' | 'ended' | 'winner_pending_deposit' | 'secured' | 'expired'
  final double currentHighestBid;
  final String? highestBidderId;
  final double? winningBid;
  final double? depositRequired;
  final DateTime? depositDeadline;
  final bool requiresManualReview;

  AuctionRound({
    required this.id,
    required this.auctionId,
    required this.roundNumber,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.currentHighestBid,
    this.highestBidderId,
    this.winningBid,
    this.depositRequired,
    this.depositDeadline,
    this.requiresManualReview = false,
  });

  factory AuctionRound.fromJson(Map<String, dynamic> json) {
    return AuctionRound(
      id: json['id'] ?? '',
      auctionId: json['auction_id'] ?? '',
      roundNumber: json['round_number'] ?? 1,
      startAt: DateTime.parse(json['start_at']),
      endAt: DateTime.parse(json['end_at']),
      status: json['status'] ?? 'upcoming',
      currentHighestBid:
          (json['current_highest_bid'] as num?)?.toDouble() ?? 0.0,
      highestBidderId: json['highest_bidder_id'],
      winningBid: (json['winning_bid'] as num?)?.toDouble(),
      depositRequired: (json['deposit_required'] as num?)?.toDouble(),
      depositDeadline: json['deposit_deadline'] != null
          ? DateTime.parse(json['deposit_deadline'])
          : null,
      requiresManualReview: json['requires_manual_review'] ?? false,
    );
  }

  bool get isTimeUpcoming {
    final now = ServerTimeService().currentServerTime;
    return now.isBefore(startAt);
  }

  bool get isTimeLive {
    final now = ServerTimeService().currentServerTime;
    return now.isAfter(startAt) && now.isBefore(endAt);
  }

  bool get isTimeEnded {
    final now = ServerTimeService().currentServerTime;
    return now.isAfter(endAt);
  }

  /// Authoritative effective status considering both DB status and current server time
  String get effectiveStatus {
    if (status == 'ended' ||
        status == 'winner_pending_deposit' ||
        status == 'secured' ||
        status == 'expired' ||
        status == 'finalised') {
      return status;
    }
    if (isTimeLive) return 'live';
    if (isTimeUpcoming) return 'upcoming';
    if (isTimeEnded) return 'ended';
    return status;
  }
}

class Auction {
  final String id;
  final String title;
  final String description;
  final double startingPrice;
  final double minIncrement;
  final String
      status; // 'draft' | 'upcoming' | 'live' | 'secured' | 'cancelled' | 'manual_review_required'
  final int reopenDurationMinutes;
  final String? createdBy;
  final DateTime createdAt;
  final List<AuctionImage> images;
  final AuctionRound? activeRound;

  // Re-Auction & Manual Review
  final String? parentAuctionId;
  final bool requiresManualReview;
  final String? manualReviewReason;

  // Business Auction attributes
  final bool isBusinessAuction;
  final String? businessProfileId;
  final String? businessName;
  final String? businessType;
  final String? businessBrand;

  // Vehicle Specification Fields
  final String vehicleType; // 'Bike' | 'Scooter'
  final String brandName;
  final String model;
  final int builtYear;
  final String yearCalendar; // 'BS' | 'AD'
  final String lotNumber;
  final String registrationNumber; // Bike/Scooter Number
  final double kilometresRun;
  final int numberOfOwners;
  final String fuelType; // 'Petrol' | 'EV'
  final String? engineOpened; // 'Yes' | 'No' (null if EV)
  final String colour;
  final double? engineCapacity; // CC (null if EV)
  final String taxStatus; // 'Fully Paid' | 'Need to Pay Tax'

  // Photo Storage Paths
  final String? bluebookFrontPath;
  final String? bluebookBackPath;
  final String? bluebookOwnerPath;
  final String? vehicleFrontPath;
  final String? vehicleBackPath;
  final String? vehicleRightPath;
  final String? vehicleLeftPath;
  final String? odometerPath;

  Auction({
    required this.id,
    required this.title,
    required this.description,
    required this.startingPrice,
    required this.minIncrement,
    required this.status,
    required this.reopenDurationMinutes,
    this.createdBy,
    required this.createdAt,
    this.images = const [],
    this.activeRound,
    this.parentAuctionId,
    this.requiresManualReview = false,
    this.manualReviewReason,
    this.isBusinessAuction = false,
    this.businessProfileId,
    this.businessName,
    this.businessType,
    this.businessBrand,
    this.vehicleType = 'Bike',
    this.brandName = 'Honda',
    this.model = 'Shine',
    this.builtYear = 2022,
    this.yearCalendar = 'BS',
    this.lotNumber = 'Lot-1',
    this.registrationNumber = 'Ba 2 Pa 1234',
    this.kilometresRun = 12000,
    this.numberOfOwners = 1,
    this.fuelType = 'Petrol',
    this.engineOpened = 'No',
    this.colour = 'Black',
    this.engineCapacity = 125,
    this.taxStatus = 'Fully Paid',
    this.bluebookFrontPath,
    this.bluebookBackPath,
    this.bluebookOwnerPath,
    this.vehicleFrontPath,
    this.vehicleBackPath,
    this.vehicleRightPath,
    this.vehicleLeftPath,
    this.odometerPath,
  });

  factory Auction.fromJson(Map<String, dynamic> json) {
    var imagesList = (json['auction_images'] as List?)
            ?.map((i) => AuctionImage.fromJson(i))
            .toList() ??
        [];

    AuctionRound? round;
    if (json['auction_rounds'] != null &&
        (json['auction_rounds'] as List).isNotEmpty) {
      round = AuctionRound.fromJson((json['auction_rounds'] as List).first);
    }

    return Auction(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      startingPrice: (json['starting_price'] as num?)?.toDouble() ?? 0.0,
      minIncrement: (json['min_increment'] as num?)?.toDouble() ?? 5000.0,
      status: json['status'] ?? 'draft',
      reopenDurationMinutes: json['reopen_duration_minutes'] ?? 30,
      createdBy: json['created_by'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      images: imagesList,
      activeRound: round,
      parentAuctionId: json['parent_auction_id'],
      requiresManualReview: json['requires_manual_review'] ?? false,
      manualReviewReason: json['manual_review_reason'],
      isBusinessAuction: json['is_business_auction'] ?? false,
      businessProfileId: json['business_profile_id'],
      businessName: json['business_name'],
      businessType: json['business_type'],
      businessBrand: json['business_brand'],
      vehicleType: json['vehicle_type'] ?? 'Bike',
      brandName: json['brand_name'] ?? (json['title']?.toString().split(' ').first ?? 'Honda'),
      model: json['model'] ?? 'Standard Model',
      builtYear: json['built_year'] ?? 2022,
      yearCalendar: json['year_calendar'] ?? 'BS',
      lotNumber: json['lot_number'] ?? 'Lot-1',
      registrationNumber: json['registration_number'] ?? 'Ba 2 Pa 1234',
      kilometresRun: (json['kilometres_run'] as num?)?.toDouble() ?? 12000.0,
      numberOfOwners: json['number_of_owners'] ?? 1,
      fuelType: json['fuel_type'] ?? 'Petrol',
      engineOpened: json['engine_opened'],
      colour: json['colour'] ?? 'Black',
      engineCapacity: (json['engine_capacity'] as num?)?.toDouble(),
      taxStatus: json['tax_status'] ?? 'Fully Paid',
      bluebookFrontPath: json['bluebook_front_path'],
      bluebookBackPath: json['bluebook_back_path'],
      bluebookOwnerPath: json['bluebook_owner_path'],
      vehicleFrontPath: json['vehicle_front_path'],
      vehicleBackPath: json['vehicle_back_path'],
      vehicleRightPath: json['vehicle_right_path'],
      vehicleLeftPath: json['vehicle_left_path'],
      odometerPath: json['odometer_path'],
    );
  }

  String get primaryImageUrl {
    if (vehicleFrontPath != null && vehicleFrontPath!.isNotEmpty) {
      return vehicleFrontPath!;
    }
    if (images.isNotEmpty) {
      final cover =
          images.firstWhere((img) => img.isCover, orElse: () => images.first);
      return cover.imageUrl;
    }
    return 'https://images.unsplash.com/photo-1558981403-c5f9899a28bc?w=800';
  }

  double get currentPrice =>
      (activeRound != null && activeRound!.currentHighestBid > 0)
          ? activeRound!.currentHighestBid
          : startingPrice;

  DateTime get endTime =>
      activeRound?.endAt ?? createdAt.add(const Duration(hours: 24));

  int get bidCount => activeRound != null && activeRound!.highestBidderId != null ? 1 : 0;

  String get effectiveStatus => activeRound?.effectiveStatus ?? status;
  bool get isLive => effectiveStatus == 'live';
  bool get isUpcoming => effectiveStatus == 'upcoming';
  bool get isCompleted =>
      effectiveStatus == 'ended' ||
      effectiveStatus == 'secured' ||
      effectiveStatus == 'finalised' ||
      effectiveStatus == 'expired';
}

class Bid {
  final String id;
  final String roundId;
  final String auctionId;
  final String bidderId;
  final double amount;
  final DateTime createdAt;
  final Profile? bidderProfile;

  Bid({
    required this.id,
    required this.roundId,
    required this.auctionId,
    required this.bidderId,
    required this.amount,
    required this.createdAt,
    this.bidderProfile,
  });

  factory Bid.fromJson(Map<String, dynamic> json) {
    return Bid(
      id: json['id'] ?? '',
      roundId: json['round_id'] ?? '',
      auctionId: json['auction_id'] ?? '',
      bidderId: json['bidder_id'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['created_at']),
      bidderProfile:
          json['profiles'] != null ? Profile.fromJson(json['profiles']) : null,
    );
  }
}

class NotificationModel {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String message;
  final String entityType;
  final String entityId;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    required this.entityType,
    required this.entityId,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      type: json['type'] ?? 'auction_started',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      entityType: json['entity_type'] ?? 'auction',
      entityId: json['entity_id'] ?? '',
      isRead: json['is_read'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class BusinessProfile {
  final String id;
  final String ownerUserId;
  final String businessType; // 'dealer', 'recondition'
  final String companyName;
  final String companyPanVatNumber;
  final String? companyPanVatDocPath;
  final String? companyRegDocPath;
  final String companyBankName;
  final String companyAccountNumber;
  final String? companyQrPath;
  final String companyPhoneNumber;
  final String primaryPersonName;
  final String primaryPersonEmail;
  final String primaryPersonPhone;
  final String? secondaryPersonName;
  final String? secondaryPersonEmail;
  final String? secondaryPersonPhone;
  final String? dealershipBrand;
  final String status; // 'pending', 'approved', 'rejected', 'suspended'
  final String? rejectionReason;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  BusinessProfile({
    required this.id,
    required this.ownerUserId,
    required this.businessType,
    required this.companyName,
    required this.companyPanVatNumber,
    this.companyPanVatDocPath,
    this.companyRegDocPath,
    required this.companyBankName,
    required this.companyAccountNumber,
    this.companyQrPath,
    required this.companyPhoneNumber,
    required this.primaryPersonName,
    required this.primaryPersonEmail,
    required this.primaryPersonPhone,
    this.secondaryPersonName,
    this.secondaryPersonEmail,
    this.secondaryPersonPhone,
    this.dealershipBrand,
    required this.status,
    this.rejectionReason,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      id: json['id']?.toString() ?? '',
      ownerUserId: json['owner_user_id']?.toString() ?? '',
      businessType: json['business_type'] ?? json['account_type'] ?? 'dealer',
      companyName: json['company_name'] ?? '',
      companyPanVatNumber: json['company_pan_vat_number'] ?? json['company_pan_number'] ?? '',
      companyPanVatDocPath: json['company_pan_vat_doc_path'] ?? json['company_pan_path'],
      companyRegDocPath: json['company_reg_doc_path'] ?? json['company_registration_path'],
      companyBankName: json['company_bank_name'] ?? '',
      companyAccountNumber: json['company_account_number'] ?? '',
      companyQrPath: json['company_qr_path'],
      companyPhoneNumber: json['company_phone_number'] ?? json['company_phone'] ?? '',
      primaryPersonName: json['primary_person_name'] ?? json['primary_name'] ?? '',
      primaryPersonEmail: json['primary_person_email'] ?? json['primary_email'] ?? '',
      primaryPersonPhone: json['primary_person_phone'] ?? json['primary_phone'] ?? '',
      secondaryPersonName: json['secondary_person_name'] ?? json['secondary_name'],
      secondaryPersonEmail: json['secondary_person_email'] ?? json['secondary_email'],
      secondaryPersonPhone: json['secondary_person_phone'] ?? json['secondary_phone'],
      dealershipBrand: json['dealership_brand'],
      status: json['status'] ?? 'pending',
      rejectionReason: json['rejection_reason'],
      reviewedAt: json['reviewed_at'] != null ? DateTime.tryParse(json['reviewed_at'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  BusinessProfile copyWith({
    String? id,
    String? ownerUserId,
    String? businessType,
    String? companyName,
    String? companyPanVatNumber,
    String? companyPanVatDocPath,
    String? companyRegDocPath,
    String? companyBankName,
    String? companyAccountNumber,
    String? companyQrPath,
    String? companyPhoneNumber,
    String? primaryPersonName,
    String? primaryPersonEmail,
    String? primaryPersonPhone,
    String? secondaryPersonName,
    String? secondaryPersonEmail,
    String? secondaryPersonPhone,
    String? dealershipBrand,
    String? status,
    String? rejectionReason,
    DateTime? reviewedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BusinessProfile(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      businessType: businessType ?? this.businessType,
      companyName: companyName ?? this.companyName,
      companyPanVatNumber: companyPanVatNumber ?? this.companyPanVatNumber,
      companyPanVatDocPath: companyPanVatDocPath ?? this.companyPanVatDocPath,
      companyRegDocPath: companyRegDocPath ?? this.companyRegDocPath,
      companyBankName: companyBankName ?? this.companyBankName,
      companyAccountNumber: companyAccountNumber ?? this.companyAccountNumber,
      companyQrPath: companyQrPath ?? this.companyQrPath,
      companyPhoneNumber: companyPhoneNumber ?? this.companyPhoneNumber,
      primaryPersonName: primaryPersonName ?? this.primaryPersonName,
      primaryPersonEmail: primaryPersonEmail ?? this.primaryPersonEmail,
      primaryPersonPhone: primaryPersonPhone ?? this.primaryPersonPhone,
      secondaryPersonName: secondaryPersonName ?? this.secondaryPersonName,
      secondaryPersonEmail: secondaryPersonEmail ?? this.secondaryPersonEmail,
      secondaryPersonPhone: secondaryPersonPhone ?? this.secondaryPersonPhone,
      dealershipBrand: dealershipBrand ?? this.dealershipBrand,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PlatformPaymentSettings {
  final int id;
  final double depositPercentage;
  final int paymentDeadlineMinutes;
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String? branchName;
  final String? qrImagePath;
  final String depositInstructions;

  PlatformPaymentSettings({
    this.id = 1,
    this.depositPercentage = 10.0,
    this.paymentDeadlineMinutes = 30,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    this.branchName,
    this.qrImagePath,
    required this.depositInstructions,
  });

  factory PlatformPaymentSettings.fromJson(Map<String, dynamic> json) {
    return PlatformPaymentSettings(
      id: json['id'] is int ? json['id'] : (int.tryParse(json['id'].toString()) ?? 1),
      depositPercentage: (json['deposit_percentage'] as num?)?.toDouble() ?? 10.0,
      paymentDeadlineMinutes: json['payment_deadline_minutes'] ?? 30,
      bankName: json['bank_name'] ?? 'Global IME Bank Nepal',
      accountName: json['account_name'] ?? 'Auction Platform Pvt Ltd',
      accountNumber: json['account_number'] ?? '0010100029384',
      branchName: json['branch_name'],
      qrImagePath: json['platform_qr_path'] ?? json['qr_image_path'],
      depositInstructions: json['payment_instructions'] ?? json['deposit_instructions'] ?? 'Deposit booking amount to platform account.',
    );
  }
}

class EvidenceSubmission {
  final String id;
  final String depositRecordId;
  final String buyerUserId;
  final String paymentMethod;
  final String? transactionReference;
  final String evidenceDocPath;
  final String? notes;
  final DateTime createdAt;

  EvidenceSubmission({
    required this.id,
    required this.depositRecordId,
    required this.buyerUserId,
    required this.paymentMethod,
    this.transactionReference,
    required this.evidenceDocPath,
    this.notes,
    required this.createdAt,
  });

  factory EvidenceSubmission.fromJson(Map<String, dynamic> json) {
    return EvidenceSubmission(
      id: json['id']?.toString() ?? '',
      depositRecordId: (json['booking_id'] ?? json['deposit_record_id'])?.toString() ?? '',
      buyerUserId: (json['winner_id'] ?? json['buyer_user_id'])?.toString() ?? '',
      paymentMethod: (json['evidence_type'] ?? json['payment_method'])?.toString() ?? 'bank_transfer',
      transactionReference: json['transaction_reference']?.toString(),
      evidenceDocPath: (json['evidence_path'] ?? json['evidence_doc_path'])?.toString() ?? '',
      notes: json['notes']?.toString(),
      createdAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'].toString()) ?? DateTime.now()
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now()),
    );
  }
}

class DepositRecord {
  final String id;
  final String bookingReference;
  final String auctionId;
  final String winningBuyerId;
  final double winningAmount;
  final double depositAmount;
  final double remainingBalance;
  final String currency;
  final String status; // 'pending_deposit', 'submitted_for_verification', 'verified', 'rejected', 'expired'
  final DateTime paymentDueAt;
  final String? latestTransactionReference;
  final String? latestEvidencePath;
  final DateTime? submittedAt;
  final String? verificationStatus;
  final DateTime? verifiedAt;
  final String? rejectionReason;
  final String? nextStepInstructions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<EvidenceSubmission> submissions;
  final Auction? auction;
  final Profile? winnerProfile;

  DepositRecord({
    required this.id,
    required this.bookingReference,
    required this.auctionId,
    required this.winningBuyerId,
    required this.winningAmount,
    required this.depositAmount,
    required this.remainingBalance,
    required this.currency,
    required this.status,
    required this.paymentDueAt,
    this.latestTransactionReference,
    this.latestEvidencePath,
    this.submittedAt,
    this.verificationStatus,
    this.verifiedAt,
    this.rejectionReason,
    this.nextStepInstructions,
    required this.createdAt,
    required this.updatedAt,
    this.submissions = const [],
    this.auction,
    this.winnerProfile,
  });

  factory DepositRecord.fromJson(Map<String, dynamic> json) {
    var subs = (json['deposit_evidence_submissions'] as List?)
            ?.map((s) => EvidenceSubmission.fromJson(Map<String, dynamic>.from(s)))
            .toList() ??
        [];

    subs.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    Auction? auc;
    if (json['auctions'] != null) {
      auc = Auction.fromJson(Map<String, dynamic>.from(json['auctions']));
    }

    Profile? profile;
    if (json['profiles'] != null) {
      profile = Profile.fromJson(Map<String, dynamic>.from(json['profiles']));
    }

    // Map database status to standard UI status
    final String rawStatus = (json['payment_status'] ?? json['status'])?.toString() ?? 'pending_deposit';
    String normalizedStatus = rawStatus;
    if (rawStatus == 'awaiting_payment') {
      normalizedStatus = 'pending_deposit';
    } else if (rawStatus == 'under_review') {
      normalizedStatus = 'submitted_for_verification';
    }

    String? latestEvidence = json['latest_evidence_path']?.toString();
    String? latestTxn = (json['latest_transaction_reference'] ?? json['transaction_reference'])?.toString();
    DateTime? submittedAt = json['submitted_at'] != null ? DateTime.tryParse(json['submitted_at'].toString()) : null;

    if (subs.isNotEmpty) {
      final lastSub = subs.last;
      if (lastSub.evidenceDocPath.isNotEmpty) {
        latestEvidence ??= lastSub.evidenceDocPath;
      }
      latestTxn ??= lastSub.transactionReference;
      submittedAt ??= lastSub.createdAt;
    }

    DateTime dueAt = DateTime.now().add(const Duration(hours: 24));
    if (json['payment_due_at'] != null) {
      final parsed = DateTime.tryParse(json['payment_due_at'].toString());
      if (parsed != null) dueAt = parsed;
    }

    return DepositRecord(
      id: json['id']?.toString() ?? '',
      bookingReference: json['booking_reference']?.toString() ?? '',
      auctionId: json['auction_id']?.toString() ?? '',
      winningBuyerId: (json['winner_id'] ?? json['winning_buyer_id'])?.toString() ?? '',
      winningAmount: (json['winning_amount'] as num?)?.toDouble() ?? 0.0,
      depositAmount: (json['deposit_amount'] as num?)?.toDouble() ?? 0.0,
      remainingBalance: (json['remaining_balance'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency']?.toString() ?? 'NPR',
      status: normalizedStatus,
      paymentDueAt: dueAt,
      latestTransactionReference: latestTxn,
      latestEvidencePath: latestEvidence,
      submittedAt: submittedAt,
      verificationStatus: (json['vehicle_reservation_status'] ?? json['verification_status'])?.toString(),
      verifiedAt: json['verified_at'] != null
          ? DateTime.tryParse(json['verified_at'].toString())
          : (json['reviewed_at'] != null ? DateTime.tryParse(json['reviewed_at'].toString()) : null),
      rejectionReason: json['rejection_reason']?.toString(),
      nextStepInstructions: (json['admin_instructions'] ?? json['next_step_instructions'])?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now() : DateTime.now(),
      submissions: subs,
      auction: auc,
      winnerProfile: profile,
    );
  }
}




