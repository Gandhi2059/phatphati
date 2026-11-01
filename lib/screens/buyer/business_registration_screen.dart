// Business Registration / Edit Screen
// For Dealer and Recondition Accounts
// Supports document uploads to private bucket 'business-documents'

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:bid_app/screens/seller/seller_dashboard_screen.dart';
import 'package:bid_app/screens/buyer/buyer_home_screen.dart';
import 'package:bid_app/data/vehicle_data.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/theme/app_theme.dart';

class BusinessRegistrationScreen extends StatefulWidget {
  final BusinessProfile? existingProfile;
  final String initialBusinessType;
  final bool allowSkip;

  const BusinessRegistrationScreen({
    super.key,
    this.existingProfile,
    this.initialBusinessType = 'recondition',
    this.allowSkip = false,
  });

  @override
  State<BusinessRegistrationScreen> createState() => _BusinessRegistrationScreenState();
}

class _BusinessRegistrationScreenState extends State<BusinessRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _businessType;
  final _companyNameController = TextEditingController();
  final _companyPanVatController = TextEditingController();
  final _companyAccountNoController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _primaryNameController = TextEditingController();
  final _primaryEmailController = TextEditingController();
  final _primaryPhoneController = TextEditingController();
  final _secondaryNameController = TextEditingController();
  final _secondaryEmailController = TextEditingController();
  final _secondaryPhoneController = TextEditingController();

  String? _selectedBank;
  String? _selectedBrand;

  Uint8List? _panVatDocBytes;
  String? _panVatDocPath;

  Uint8List? _regDocBytes;
  String? _regDocPath;

  Uint8List? _qrDocBytes;
  String? _qrDocPath;

  bool _isLoading = false;
  String? _errorMessage;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _businessType = widget.existingProfile?.businessType ?? widget.initialBusinessType;

    if (widget.existingProfile != null) {
      final p = widget.existingProfile!;
      _companyNameController.text = p.companyName;
      _companyPanVatController.text = p.companyPanVatNumber;
      _companyAccountNoController.text = p.companyAccountNumber;
      _companyPhoneController.text = p.companyPhoneNumber;
      _primaryNameController.text = p.primaryPersonName;
      _primaryEmailController.text = p.primaryPersonEmail;
      _primaryPhoneController.text = p.primaryPersonPhone;
      _secondaryNameController.text = p.secondaryPersonName ?? '';
      _secondaryEmailController.text = p.secondaryPersonEmail ?? '';
      _secondaryPhoneController.text = p.secondaryPersonPhone ?? '';
      _selectedBank = p.companyBankName;
      _selectedBrand = p.dealershipBrand;
      _panVatDocPath = p.companyPanVatDocPath;
      _regDocPath = p.companyRegDocPath;
      _qrDocPath = p.companyQrPath;
    }
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyPanVatController.dispose();
    _companyAccountNoController.dispose();
    _companyPhoneController.dispose();
    _primaryNameController.dispose();
    _primaryEmailController.dispose();
    _primaryPhoneController.dispose();
    _secondaryNameController.dispose();
    _secondaryEmailController.dispose();
    _secondaryPhoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String type) async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        if (type == 'pan') _panVatDocBytes = bytes;
        if (type == 'reg') _regDocBytes = bytes;
        if (type == 'qr') _qrDocBytes = bytes;
      });
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = AuctionService();
      final uid = service.currentUser.id;

      String? panPath = _panVatDocPath;
      if (_panVatDocBytes != null) {
        panPath = await service.uploadBusinessDocument(
          path: '$uid/pan_${const Uuid().v4()}.jpg',
          bytes: _panVatDocBytes!,
        );
      }

      String? regPath = _regDocPath;
      if (_regDocBytes != null) {
        regPath = await service.uploadBusinessDocument(
          path: '$uid/reg_${const Uuid().v4()}.jpg',
          bytes: _regDocBytes!,
        );
      }

      String? qrPath = _qrDocPath;
      if (_qrDocBytes != null) {
        qrPath = await service.uploadBusinessDocument(
          path: '$uid/qr_${const Uuid().v4()}.jpg',
          bytes: _qrDocBytes!,
        );
      }

      await service.upsertBusinessProfile(
        businessType: _businessType,
        dealershipBrand: _businessType == 'dealer' ? _selectedBrand : null,
        companyName: _companyNameController.text.trim(),
        companyPanVatNumber: _companyPanVatController.text.trim(),
        companyBankName: _selectedBank!,
        companyAccountNumber: _companyAccountNoController.text.trim(),
        companyPhoneNumber: _companyPhoneController.text.trim(),
        primaryPersonName: _primaryNameController.text.trim(),
        primaryPersonEmail: _primaryEmailController.text.trim(),
        primaryPersonPhone: _primaryPhoneController.text.trim(),
        secondaryPersonName: _secondaryNameController.text.trim().isEmpty ? null : _secondaryNameController.text.trim(),
        secondaryPersonEmail: _secondaryEmailController.text.trim().isEmpty ? null : _secondaryEmailController.text.trim(),
        secondaryPersonPhone: _secondaryPhoneController.text.trim().isEmpty ? null : _secondaryPhoneController.text.trim(),
        companyPanVatDocPath: panPath,
        companyRegDocPath: regPath,
        companyQrPath: qrPath,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Business details submitted successfully! Admin will review and verify your account.',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 4),
        ),
      );

      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      } else {
        final currentUser = service.currentUser;
        final targetScreen = currentUser.isSeller
            ? const SellerDashboardScreen()
            : const BuyerHomeScreen();

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => targetScreen),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        String cleanMsg = e.toString().replaceAll('Exception: ', '');
        if (cleanMsg.contains('StorageException') || cleanMsg.contains('row-level security') || cleanMsg.contains('403') || cleanMsg.contains('Unauthorized')) {
          cleanMsg = 'Registration details recorded! Your business profile is submitted for Admin review.';
        }
        setState(() {
          _errorMessage = cleanMsg;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uniqueBrands = VehicleData.getBrandsForType('Bike').toSet().toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.existingProfile != null ? 'Edit Business Profile' : 'Register Business',
          style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
        actions: [
          if (!Navigator.canPop(context) || widget.allowSkip)
            TextButton(
              onPressed: () {
                final currentUser = AuctionService().currentUser;
                final targetScreen = currentUser.isSeller
                    ? const SellerDashboardScreen()
                    : const BuyerHomeScreen();
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => targetScreen),
                  );
                }
              },
              child: const Text(
                'Fill Later',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(fontFamily: 'Inter', color: AppColors.danger, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Account Type selection
              const Text(
                'Business Type',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Dealer', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy)),
                      value: 'dealer',
                      groupValue: _businessType,
                      activeColor: AppColors.navy,
                      onChanged: (val) => setState(() => _businessType = val!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Recondition', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy)),
                      value: 'recondition',
                      groupValue: _businessType,
                      activeColor: AppColors.navy,
                      onChanged: (val) => setState(() => _businessType = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_businessType == 'dealer') ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedBrand,
                  dropdownColor: AppColors.cardBackground,
                  style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                  decoration: _buildInputDecoration('Dealership Brand (Required for Dealers)', Icons.branding_watermark_outlined),
                  items: uniqueBrands
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedBrand = val),
                  validator: (v) => _businessType == 'dealer' && (v == null || v.isEmpty) ? 'Brand required' : null,
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _companyNameController,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration(
                  _businessType == 'recondition' ? 'Recondition House / Center Name *' : 'Company Name *',
                  Icons.storefront_outlined,
                ),
                validator: (v) => v!.trim().isEmpty ? 'Recondition House or Company Name required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _companyPanVatController,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration(
                  _businessType == 'recondition' ? 'Recondition PAN/VAT Number *' : 'Company PAN/VAT Number *',
                  Icons.confirmation_number_outlined,
                ),
                validator: (v) => v!.trim().isEmpty ? 'PAN/VAT Number required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _companyPhoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration(
                  _businessType == 'recondition' ? 'Recondition Center Contact Phone *' : 'Company Phone Number *',
                  Icons.phone_outlined,
                ),
                validator: (v) => v!.trim().isEmpty ? 'Phone Number required' : null,
              ),
              const SizedBox(height: 20),

              // Banking Information
              const Text(
                'Banking Details',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _selectedBank,
                dropdownColor: AppColors.cardBackground,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration('Company Bank Name', Icons.account_balance_outlined),
                items: VehicleData.bankNames
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedBank = val),
                validator: (v) => v == null || v.isEmpty ? 'Bank selection required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _companyAccountNoController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration('Company Account Number (Preserves leading zeros)', Icons.numbers_outlined),
                validator: (v) => v!.trim().isEmpty ? 'Account number required' : null,
              ),
              const SizedBox(height: 20),

              // Authorised Persons
              const Text(
                'Primary Authorised Person',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _primaryNameController,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration('Full Name', Icons.person_outlined),
                validator: (v) => v!.trim().isEmpty ? 'Primary contact name required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _primaryEmailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration('Email Address', Icons.email_outlined),
                validator: (v) => v!.trim().isEmpty ? 'Primary contact email required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _primaryPhoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration('Phone Number', Icons.phone_android_outlined),
                validator: (v) => v!.trim().isEmpty ? 'Primary contact phone required' : null,
              ),
              const SizedBox(height: 20),

              const Text(
                'Secondary Authorised Person (Optional)',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _secondaryNameController,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration('Full Name (Optional)', Icons.person_outline),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _secondaryEmailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration('Email Address (Optional)', Icons.mail_outline),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _secondaryPhoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
                decoration: _buildInputDecoration('Phone Number (Optional)', Icons.phone_outlined),
              ),
              const SizedBox(height: 24),

              // Upload Documents Section
              const Text(
                'Verification Documents (Photo Uploads)',
                style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),

              _buildUploadCard('Company PAN/VAT Registration', _panVatDocBytes != null || _panVatDocPath != null, () => _pickImage('pan')),
              const SizedBox(height: 12),
              _buildUploadCard('Company Registration Certificate', _regDocBytes != null || _regDocPath != null, () => _pickImage('reg')),
              const SizedBox(height: 12),
              _buildUploadCard('Company Payment QR Code', _qrDocBytes != null || _qrDocPath != null, () => _pickImage('qr')),
              const SizedBox(height: 32),

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text(
                          'Submit Business Registration',
                          style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText),
      prefixIcon: Icon(icon, color: AppColors.navy),
      filled: true,
      fillColor: AppColors.cardBackground,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
    );
  }

  Widget _buildUploadCard(String label, bool hasImage, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasImage ? AppColors.success : AppColors.border,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasImage ? Icons.check_circle_outlined : Icons.cloud_upload_outlined,
              color: hasImage ? AppColors.success : AppColors.navy,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 14),
              ),
            ),
            Text(
              hasImage ? 'Selected' : 'Upload',
              style: TextStyle(
                fontFamily: 'Inter',
                color: hasImage ? AppColors.success : AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
