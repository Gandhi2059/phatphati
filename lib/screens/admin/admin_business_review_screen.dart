// Admin Business Review Screen
// Allows Admins to inspect full business registration details, view inline uploaded document thumbnails, verify Dealer/Reconditioner account status, and enter decline comments.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/theme/app_theme.dart';

class AdminBusinessReviewScreen extends StatefulWidget {
  const AdminBusinessReviewScreen({super.key});

  @override
  State<AdminBusinessReviewScreen> createState() => _AdminBusinessReviewScreenState();
}

class _AdminBusinessReviewScreenState extends State<AdminBusinessReviewScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<BusinessProfile> _allProfiles = [];
  final Map<String, Set<String>> _verifiedDocTypes = {};
  final Map<String, String> _signedUrlCache = {};
  final Map<String, TextEditingController> _inlineCommentControllers = {};
  StreamSubscription<List<BusinessProfile>>? _profileSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadProfiles();
    _profileSub = AuctionService().businessProfileStream.listen((profiles) {
      if (mounted) {
        setState(() {
          _allProfiles = profiles;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _profileSub?.cancel();
    for (final controller in _inlineCommentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    final profiles = await AuctionService().fetchPendingBusinessProfiles();
    
    // Cache signed URLs for all uploaded documents for fast inline rendering
    for (final p in profiles) {
      _inlineCommentControllers.putIfAbsent(p.id, () => TextEditingController(text: p.rejectionReason ?? ''));
      if (p.companyPanVatDocPath != null) _preloadSignedUrl(p.companyPanVatDocPath!);
      if (p.companyRegDocPath != null) _preloadSignedUrl(p.companyRegDocPath!);
      if (p.companyQrPath != null) _preloadSignedUrl(p.companyQrPath!);
    }

    if (mounted) {
      setState(() {
        _allProfiles = profiles;
        _isLoading = false;
      });
    }
  }

  Future<void> _preloadSignedUrl(String path) async {
    if (_signedUrlCache.containsKey(path)) return;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      _signedUrlCache[path] = path;
      return;
    }
    try {
      final url = await AuctionService().getSignedUrl('business-documents', path);
      if (mounted) {
        setState(() {
          _signedUrlCache[path] = url;
        });
      }
    } catch (_) {}
  }

  List<BusinessProfile> _filterByStatus(String status) {
    return _allProfiles.where((p) => p.status == status).toList();
  }

  bool _isDocVerified(String businessId, String docType) {
    return _verifiedDocTypes[businessId]?.contains(docType) ?? false;
  }

  void _toggleDocVerification(String businessId, String docType) {
    setState(() {
      _verifiedDocTypes.putIfAbsent(businessId, () => <String>{});
      if (_verifiedDocTypes[businessId]!.contains(docType)) {
        _verifiedDocTypes[businessId]!.remove(docType);
      } else {
        _verifiedDocTypes[businessId]!.add(docType);
      }
    });
  }

  void _verifyAllDocs(BusinessProfile profile) {
    setState(() {
      final docs = <String>{};
      if (profile.companyPanVatDocPath != null) docs.add('pan');
      if (profile.companyRegDocPath != null) docs.add('reg');
      if (profile.companyQrPath != null) docs.add('qr');
      _verifiedDocTypes[profile.id] = docs;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('All documents marked as VERIFIED for ${profile.companyName}.', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleReview(BusinessProfile profile, String action) async {
    String? rejectionReason = profile.rejectionReason;
    if (action == 'rejected') {
      rejectionReason = await _showRejectionDialog(profile.companyName, initialReason: profile.rejectionReason);
      if (rejectionReason == null || rejectionReason.trim().isEmpty) return;
    }

    try {
      await AuctionService().adminReviewBusiness(
        businessId: profile.id,
        newStatus: action,
        rejectionReason: rejectionReason,
      );
      if (!mounted) return;
      
      final typeLabel = profile.businessType.toUpperCase();
      final actionLabel = action == 'approved'
          ? 'ACCEPTED & APPROVED as $typeLabel'
          : (action == 'pending' ? 'MOVED TO PENDING (EDIT ALLOWED)' : 'DECLINED / REJECTED');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Application for ${profile.companyName} $actionLabel successfully.',
            style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: action == 'approved'
              ? AppColors.success
              : (action == 'pending' ? AppColors.amber : AppColors.danger),
        ),
      );
      _loadProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action failed: $e', style: const TextStyle(fontFamily: 'Inter', color: Colors.white)),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _confirmAndDeleteBusiness(BusinessProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Registration?',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete the rejected business registration for "${profile.companyName}"?\n\nThis will remove the registration record and reset the user\'s business verification status so they may re-apply if necessary.',
          style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            label: const Text('Delete Permanently', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AuctionService().deleteBusinessProfile(profile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Business profile for "${profile.companyName}" has been permanently deleted.',
            style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.navy,
        ),
      );
      _loadProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete registration: $e', style: const TextStyle(fontFamily: 'Inter', color: Colors.white)),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _handleSetPending(BusinessProfile profile) async {
    final controller = TextEditingController(text: profile.rejectionReason ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.pending_actions_rounded, color: AppColors.amber, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Move to Pending (Allow Edit)',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Move "${profile.companyName}" back to Pending?\n\nThis will allow the applicant (${profile.businessType.toUpperCase()}) to edit their business details, banking info, and upload new documents directly.',
              style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            const Text(
              'Reason / Correction Instructions for Applicant:',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. Please upload clearer PAN photo or fix bank account details...',
                hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            label: const Text('Set as Pending', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AuctionService().adminReviewBusiness(
        businessId: profile.id,
        newStatus: 'pending',
        rejectionReason: controller.text.trim().isEmpty ? null : controller.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${profile.companyName} is now Pending. The applicant can now edit and resubmit their details.',
            style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.navy,
        ),
      );
      _loadProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set pending: $e', style: const TextStyle(fontFamily: 'Inter', color: Colors.white)),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _saveComment(BusinessProfile profile, String commentText) async {
    final comment = commentText.trim();
    if (comment.isEmpty) return;
    try {
      await AuctionService().adminReviewBusiness(
        businessId: profile.id,
        newStatus: profile.status,
        rejectionReason: comment,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin note / comment saved successfully.', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primary,
          duration: Duration(seconds: 2),
        ),
      );
      _loadProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save comment: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _addOrEditComment(BusinessProfile profile) async {
    final comment = await _showRejectionDialog(
      profile.companyName,
      titleText: 'Admin Note / Comment for ${profile.companyName}',
      hintText: 'Enter internal notes or decline comments regarding business verification...',
      initialReason: profile.rejectionReason,
    );
    if (comment != null && comment.isNotEmpty) {
      await _saveComment(profile, comment);
    }
  }

  Future<String?> _showRejectionDialog(
    String companyName, {
    String titleText = 'Decline / Reject Application',
    String hintText = 'Specify exact reason for declining (e.g. Unreadable PAN doc, Bank details mismatch)...',
    String? initialReason,
  }) async {
    final controller = TextEditingController(text: initialReason ?? '');
    final quickReasons = [
      'Unreadable / Blurry Document',
      'PAN / VAT Number Mismatch',
      'Registration Certificate Expired / Invalid',
      'Bank Account Details Mismatch',
      'Missing Authorized Signature / Stamp',
    ];

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.rate_review_rounded, color: AppColors.navy, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titleText,
                        style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Company: $companyName',
                  style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Templates:',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: quickReasons.map((reason) {
                      return ChoiceChip(
                        label: Text(reason, style: const TextStyle(fontFamily: 'Inter', fontSize: 11)),
                        selected: controller.text.contains(reason),
                        selectedColor: AppColors.primary.withValues(alpha: 0.15),
                        onSelected: (selected) {
                          setDialogState(() {
                            if (controller.text.trim().isEmpty) {
                              controller.text = reason;
                            } else if (!controller.text.contains(reason)) {
                              controller.text = '${controller.text.trim()}; $reason';
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Decline Reason / Admin Note *:',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                icon: const Icon(Icons.save_rounded, size: 16, color: Colors.white),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                label: const Text('Save Comment', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openFullFormReviewModal(BusinessProfile p) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.cardBackground,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 750),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Business Registration Form Review',
                            style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          Text(
                            p.companyName,
                            style: const TextStyle(fontFamily: 'Inter', color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.navy),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Submitted Application Form Data:', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              _buildDetailRow('Account Category', p.businessType.toUpperCase()),
                              _buildDetailRow('Dealership Brand', p.dealershipBrand ?? 'N/A'),
                              _buildDetailRow('Company Name', p.companyName),
                              _buildDetailRow('PAN / VAT No', p.companyPanVatNumber),
                              _buildDetailRow('Company Phone', p.companyPhoneNumber),
                              _buildDetailRow('Bank Name', p.companyBankName),
                              _buildDetailRow('Account No', p.companyAccountNumber),
                              _buildDetailRow('Primary Authorised', '${p.primaryPersonName} (${p.primaryPersonPhone})'),
                              _buildDetailRow('Primary Email', p.primaryPersonEmail),
                              _buildDetailRow('Secondary Contact', '${p.secondaryPersonName ?? 'N/A'} (${p.secondaryPersonPhone ?? 'N/A'})'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Uploaded Form Documents:', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        _buildDocCardWithPreview(
                          docTitle: 'PAN / VAT Document',
                          docPath: p.companyPanVatDocPath,
                          isVerified: _isDocVerified(p.id, 'pan'),
                          businessId: p.id,
                          docType: 'pan',
                        ),
                        const SizedBox(height: 8),
                        _buildDocCardWithPreview(
                          docTitle: 'Business Registration Certificate',
                          docPath: p.companyRegDocPath,
                          isVerified: _isDocVerified(p.id, 'reg'),
                          businessId: p.id,
                          docType: 'reg',
                        ),
                        const SizedBox(height: 8),
                        _buildDocCardWithPreview(
                          docTitle: 'Company QR / Bank Proof',
                          docPath: p.companyQrPath,
                          isVerified: _isDocVerified(p.id, 'qr'),
                          businessId: p.id,
                          docType: 'qr',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (p.status == 'approved') ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _handleSetPending(p);
                          },
                          icon: const Icon(Icons.pending_actions_rounded, color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.amber, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          label: const Text('MOVE TO PENDING (ALLOW EDIT)', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _handleReview(p, 'rejected');
                          },
                          icon: const Icon(Icons.cancel_rounded, color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          label: const Text('REJECT / REVOKE', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ] else if (p.status == 'rejected') ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmAndDeleteBusiness(p);
                          },
                          icon: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          label: const Text('DELETE REGISTRATION', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _handleSetPending(p);
                          },
                          icon: const Icon(Icons.replay_rounded, color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.amber, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          label: const Text('SET AS PENDING', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _handleReview(p, 'approved');
                          },
                          icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          label: const Text('ACCEPT', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _handleReview(p, 'rejected');
                          },
                          icon: const Icon(Icons.cancel_rounded, color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          label: const Text('REJECT FORM', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _handleReview(p, 'approved');
                          },
                          icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          label: const Text('ACCEPT FORM', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openFullImageViewer(String path, String docTitle, String businessId, String docType) async {
    final signedUrl = _signedUrlCache[path] ?? await AuctionService().getSignedUrl('business-documents', path);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isVerified = _isDocVerified(businessId, docType);
            return Dialog(
              backgroundColor: AppColors.cardBackground,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                padding: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            docTitle,
                            style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.navy),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: InteractiveViewer(
                          panEnabled: true,
                          boundaryMargin: const EdgeInsets.all(20),
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Image.network(
                            signedUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.background,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.description_rounded, size: 72, color: AppColors.primary),
                                    const SizedBox(height: 12),
                                    Text(
                                      docTitle,
                                      style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 6),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      child: Text(
                                        'Uploaded File Reference:\n$path',
                                        style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _toggleDocVerification(businessId, docType);
                              setModalState(() {});
                            },
                            icon: Icon(
                              isVerified ? Icons.check_circle : Icons.verified_outlined,
                              color: Colors.white,
                            ),
                            label: Text(
                              isVerified ? 'DOCUMENT VERIFIED ✓' : 'MARK DOCUMENT AS VERIFIED',
                              style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isVerified ? AppColors.success : AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
        title: const Text('Business Registrations & Approvals', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.navy),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.secondaryText,
          labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.normal),
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
            Tab(text: 'Suspended'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_filterByStatus('pending')),
                _buildList(_filterByStatus('approved')),
                _buildList(_filterByStatus('rejected')),
                _buildList(_filterByStatus('suspended')),
              ],
            ),
    );
  }

  Widget _buildList(List<BusinessProfile> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text('No business profiles in this category.', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final p = list[i];
        final accountTypeName = p.businessType.toUpperCase(); // 'DEALER' or 'RECONDITIONER'

        final isPanVerified = _isDocVerified(p.id, 'pan');
        final isRegVerified = _isDocVerified(p.id, 'reg');
        final isQrVerified = _isDocVerified(p.id, 'qr');

        final totalUploadedDocs = (p.companyPanVatDocPath != null ? 1 : 0) +
            (p.companyRegDocPath != null ? 1 : 0) +
            (p.companyQrPath != null ? 1 : 0);
        final verifiedCount = (isPanVerified ? 1 : 0) + (isRegVerified ? 1 : 0) + (isQrVerified ? 1 : 0);

        final inlineController = _inlineCommentControllers[p.id] ?? TextEditingController(text: p.rejectionReason ?? '');

        return Card(
          color: AppColors.cardBackground,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ==========================================
                // HEADER: COMPANY NAME & DEALER VERIFICATION BADGE
                // ==========================================
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.companyName,
                            style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(height: 2),
                          if (p.dealershipBrand != null && p.dealershipBrand!.isNotEmpty)
                            Text(
                              'Authorized Brand: ${p.dealershipBrand}',
                              style: const TextStyle(fontFamily: 'Inter', color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Prominent Dealer / Reconditioner Verification Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.status == 'approved'
                            ? AppColors.success.withValues(alpha: 0.15)
                            : (p.status == 'rejected'
                                ? AppColors.danger.withValues(alpha: 0.15)
                                : AppColors.amber.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: p.status == 'approved'
                              ? AppColors.success
                              : (p.status == 'rejected' ? AppColors.danger : AppColors.amber),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            p.status == 'approved'
                                ? Icons.verified_rounded
                                : (p.status == 'rejected' ? Icons.cancel_rounded : Icons.pending_actions_rounded),
                            size: 16,
                            color: p.status == 'approved'
                                ? AppColors.success
                                : (p.status == 'rejected' ? AppColors.danger : AppColors.amber),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            p.status == 'approved'
                                ? 'VERIFIED $accountTypeName ✓'
                                : (p.status == 'rejected'
                                    ? 'DECLINED $accountTypeName'
                                    : 'PENDING $accountTypeName'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: p.status == 'approved'
                                  ? AppColors.success
                                  : (p.status == 'rejected' ? AppColors.danger : AppColors.amber),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (p.status == 'approved') ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Move to Pending (Allow Edit)',
                        icon: const Icon(Icons.pending_actions_rounded, color: AppColors.amber, size: 24),
                        onPressed: () => _handleSetPending(p),
                      ),
                    ],
                    if (p.status == 'rejected') ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Permanently Delete Registration',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 22),
                        onPressed: () => _confirmAndDeleteBusiness(p),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // Details Grid Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow('PAN / VAT No', p.companyPanVatNumber),
                      _buildDetailRow('Company Phone', p.companyPhoneNumber),
                      _buildDetailRow('Bank Name', p.companyBankName),
                      _buildDetailRow('Account No', p.companyAccountNumber),
                      _buildDetailRow('Primary Authorised', '${p.primaryPersonName} (${p.primaryPersonPhone})'),
                      _buildDetailRow('Primary Email', p.primaryPersonEmail),
                      if (p.secondaryPersonName != null && p.secondaryPersonName!.isNotEmpty)
                        _buildDetailRow('Secondary Contact', '${p.secondaryPersonName} (${p.secondaryPersonPhone ?? 'No Phone'})'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // REVIEW FULL FORM BUTTON
                OutlinedButton.icon(
                  onPressed: () => _openFullFormReviewModal(p),
                  icon: const Icon(Icons.assignment_turned_in_outlined, size: 18, color: AppColors.primary),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  label: const Text(
                    'REVIEW FULL REGISTRATION FORM & DOCUMENTS',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),

                // ==========================================
                // 1. VISIBLE UPLOADED DOCUMENTS & VERIFICATION SECTION
                // ==========================================
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.badge_outlined, size: 18, color: AppColors.primary),
                              SizedBox(width: 6),
                              Text(
                                'DOCUMENT VERIFICATION SECTION',
                                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => _verifyAllDocs(p),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.done_all_rounded, size: 14, color: AppColors.success),
                                  SizedBox(width: 4),
                                  Text(
                                    'MARK ALL VERIFIED',
                                    style: TextStyle(fontFamily: 'Inter', color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Verified Documents: $verifiedCount of $totalUploadedDocs completed',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: verifiedCount == totalUploadedDocs && totalUploadedDocs > 0 ? AppColors.success : AppColors.secondaryText,
                        ),
                      ),
                      const Divider(height: 16),

                      // Document 1: PAN / VAT
                      _buildDocCardWithPreview(
                        docTitle: 'PAN / VAT Document',
                        docPath: p.companyPanVatDocPath,
                        isVerified: isPanVerified,
                        businessId: p.id,
                        docType: 'pan',
                      ),
                      const SizedBox(height: 10),

                      // Document 2: Registration Certificate
                      _buildDocCardWithPreview(
                        docTitle: 'Business Registration Certificate',
                        docPath: p.companyRegDocPath,
                        isVerified: isRegVerified,
                        businessId: p.id,
                        docType: 'reg',
                      ),
                      const SizedBox(height: 10),

                      // Document 3: Company QR / Bank
                      _buildDocCardWithPreview(
                        docTitle: 'Company QR / Payment Proof',
                        docPath: p.companyQrPath,
                        isVerified: isQrVerified,
                        businessId: p.id,
                        docType: 'qr',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ==========================================
                // 2. ACTIVE DECLINE & ADMIN COMMENT SECTION
                // ==========================================
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (p.status == 'rejected' ? AppColors.danger : AppColors.amber).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: (p.status == 'rejected' ? AppColors.danger : AppColors.amber).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                p.status == 'rejected' ? Icons.cancel_outlined : Icons.rate_review_outlined,
                                size: 16,
                                color: p.status == 'rejected' ? AppColors.danger : AppColors.amber,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                p.status == 'rejected' ? 'DECLINE / REJECTION REASON SECTION' : 'ADMIN COMMENT / REVIEW NOTES',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.bold,
                                  color: p.status == 'rejected' ? AppColors.danger : AppColors.amber,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => _addOrEditComment(p),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'OPEN EDITOR',
                                style: TextStyle(fontFamily: 'Inter', color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Direct Inline Comment Input Box
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: inlineController,
                              maxLines: 2,
                              style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: p.status == 'rejected'
                                    ? 'Enter decline reason for applicant...'
                                    : 'Add internal admin verification note or comment...',
                                hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12),
                                filled: true,
                                fillColor: AppColors.cardBackground,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _saveComment(p, inlineController.text),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('SAVE', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ==========================================
                // 3. ACCOUNT VERIFICATION ACTION BUTTONS
                // ==========================================
                Row(
                  children: [
                    if (p.status == 'rejected') ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _confirmAndDeleteBusiness(p),
                          icon: const Icon(Icons.delete_forever_rounded, size: 18, color: Colors.white),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          label: const Text(
                            'DELETE REJECTED REGISTRATION',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _handleReview(p, 'approved'),
                          icon: const Icon(Icons.verified_user_rounded, size: 18, color: Colors.white),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          label: const Text(
                            'RECONSIDER & APPROVE',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                    ] else if (p.status == 'approved') ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _handleSetPending(p),
                          icon: const Icon(Icons.pending_actions_rounded, size: 18, color: Colors.white),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.amber,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          label: const Text(
                            'MOVE TO PENDING (ALLOW EDIT)',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _handleReview(p, 'rejected'),
                          icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.white),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          label: const Text(
                            'REJECT / REVOKE',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ] else ...[
                      if (p.status != 'approved')
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _handleReview(p, 'approved'),
                            icon: const Icon(Icons.verified_user_rounded, size: 18, color: Colors.white),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            label: Text(
                              'ACCEPT & APPROVE $accountTypeName',
                              style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      if (p.status != 'approved') const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _handleReview(p, 'rejected'),
                          icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.white),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          label: const Text(
                            'REJECT / DECLINE FORM',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12)),
          Flexible(
            child: Text(
              value.isEmpty ? 'N/A' : value,
              style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 12),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocCardWithPreview({
    required String docTitle,
    required String? docPath,
    required bool isVerified,
    required String businessId,
    required String docType,
  }) {
    final hasDoc = docPath != null && docPath.isNotEmpty;
    final signedUrl = hasDoc ? _signedUrlCache[docPath] : null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isVerified
            ? AppColors.success.withValues(alpha: 0.05)
            : (hasDoc ? AppColors.navy.withValues(alpha: 0.03) : AppColors.border.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVerified
              ? AppColors.success
              : (hasDoc ? AppColors.navy.withValues(alpha: 0.2) : AppColors.border),
        ),
      ),
      child: Row(
        children: [
          // Inline Document Image Thumbnail
          GestureDetector(
            onTap: hasDoc ? () => _openFullImageViewer(docPath, docTitle, businessId, docType) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 60,
                height: 60,
                color: AppColors.background,
                child: hasDoc
                    ? (signedUrl != null
                        ? Image.network(
                            signedUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.file_present_rounded, color: AppColors.primary, size: 28),
                            ),
                          )
                        : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                    : const Center(child: Icon(Icons.error_outline_rounded, color: AppColors.secondaryText, size: 24)),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Title & Verification Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  docTitle,
                  style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  hasDoc ? (isVerified ? 'VERIFIED ✓' : 'Submitted (Tap image to view)') : 'Document Not Uploaded',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: isVerified ? FontWeight.bold : FontWeight.normal,
                    color: hasDoc ? (isVerified ? AppColors.success : AppColors.amber) : AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),

          // Verification Toggle Action
          if (hasDoc) ...[
            InkWell(
              onTap: () => _toggleDocVerification(businessId, docType),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isVerified ? AppColors.success : AppColors.navy,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isVerified ? 'VERIFIED ✓' : 'VERIFY',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.border.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'MISSING',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
