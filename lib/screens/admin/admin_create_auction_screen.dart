// Screen: Create & Edit Bike/Scooter Vehicle Auction Form
// Supports 16 vehicle fields, dependent brand/model dropdowns, EV vs Petrol engine logic, 8 photo uploads (3 private Blue Book + 4 vehicle sides + 1 Odometer), pricing & server timing.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bid_app/data/vehicle_data.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/services/auction_service.dart';
import 'package:bid_app/services/server_time_service.dart';
import 'package:bid_app/theme/app_theme.dart';

class AdminCreateAuctionScreen extends StatefulWidget {
  final Auction? auction;

  const AdminCreateAuctionScreen({super.key, this.auction});

  @override
  State<AdminCreateAuctionScreen> createState() =>
      _AdminCreateAuctionScreenState();
}

class _AdminCreateAuctionScreenState extends State<AdminCreateAuctionScreen> {
  final AuctionService _service = AuctionService();
  final _formKey = GlobalKey<FormState>();

  // 0. Business Auction Flag
  bool _isBusinessAuction = false;

  // 1. Classification & Brand/Model
  String _vehicleType = 'Bike';
  String? _selectedBrand;
  String? _selectedModel;
  final _customModelController = TextEditingController();

  // 2. Registration & History
  int _builtYear = DateTime.now().year;
  String _yearCalendar = 'BS'; // 'BS' or 'AD'
  final _lotNumberController = TextEditingController();
  final _regNumberController = TextEditingController();
  final _kmRunController = TextEditingController();
  final _ownersCountController = TextEditingController(text: '1');
  String _taxStatus = 'Fully Paid';

  // 3. Specifications & Powertrain
  String _fuelType = 'Petrol'; // 'Petrol' or 'EV'
  String? _engineOpened = 'No'; // 'Yes' or 'No', null if EV
  String _colour = 'Black';
  final _customColourController = TextEditingController();
  final _engineCapacityCcController = TextEditingController(); // CC, null if EV

  // 4. Financial & Server Timing
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _incrementController = TextEditingController();
  final _reopenMinutesController = TextEditingController(text: '30');

  bool _startImmediately = true; // Default to Live immediately on creation
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;

  // 5. Photo Upload States (8 Photos Required)
  // Blue Book Documents (Private)
  Uint8List? _bbFrontBytes; String? _bbFrontPath;
  Uint8List? _bbBackBytes;  String? _bbBackPath;
  Uint8List? _bbOwnerBytes; String? _bbOwnerPath;

  // Vehicle Photos (Public)
  Uint8List? _vFrontBytes; String? _vFrontPath;
  Uint8List? _vBackBytes;  String? _vBackPath;
  Uint8List? _vRightBytes; String? _vRightPath;
  Uint8List? _vLeftBytes;  String? _vLeftPath;

  // Odometer Photo (Public)
  Uint8List? _odoBytes;    String? _odoPath;

  bool _isSubmitting = false;
  String? _uploadProgressMessage;

  @override
  void initState() {
    super.initState();
    _initFormFields();
  }

  void _initFormFields() {
    final now = ServerTimeService().currentNepalTime;
    final endDateTime = now.add(const Duration(hours: 2));
    _startDate = now;
    _startTime = TimeOfDay.fromDateTime(now);
    _endDate = endDateTime;
    _endTime = TimeOfDay.fromDateTime(endDateTime);

    if (widget.auction != null) {
      final a = widget.auction!;
      _isBusinessAuction = a.isBusinessAuction;
      _vehicleType = a.vehicleType.isNotEmpty ? a.vehicleType : 'Bike';
      _selectedBrand = a.brandName.isNotEmpty ? a.brandName : null;
      _selectedModel = a.model.isNotEmpty ? a.model : null;

      _builtYear = a.builtYear > 1900 ? a.builtYear : 2079;
      _yearCalendar = a.yearCalendar.isNotEmpty ? a.yearCalendar : 'BS';
      _lotNumberController.text = a.lotNumber;
      _regNumberController.text = a.registrationNumber;
      _kmRunController.text = a.kilometresRun > 0 ? a.kilometresRun.toStringAsFixed(0) : '';
      _ownersCountController.text = a.numberOfOwners.toString();
      _taxStatus = a.taxStatus.isNotEmpty ? a.taxStatus : 'Fully Paid';

      _fuelType = a.fuelType.isNotEmpty ? a.fuelType : 'Petrol';
      _engineOpened = _fuelType == 'EV' ? null : (a.engineOpened ?? 'No');
      _colour = VehicleData.commonColours.contains(a.colour) ? a.colour : 'Other';
      if (_colour == 'Other') _customColourController.text = a.colour;

      if (_fuelType == 'Petrol' && a.engineCapacity != null) {
        _engineCapacityCcController.text = a.engineCapacity!.toStringAsFixed(0);
      }

      _descController.text = a.description;
      _priceController.text = a.startingPrice > 0 ? a.startingPrice.toStringAsFixed(0) : '';
      _incrementController.text = a.minIncrement > 0 ? a.minIncrement.toStringAsFixed(0) : '';
      _reopenMinutesController.text = a.reopenDurationMinutes.toString();

      final start = ServerTimeService.toNepalTime(a.activeRound?.startAt ?? a.createdAt);
      final end = ServerTimeService.toNepalTime(a.activeRound?.endAt ?? a.createdAt.add(const Duration(hours: 2)));
      _startDate = start;
      _startTime = TimeOfDay.fromDateTime(start);
      _endDate = end;
      _endTime = TimeOfDay.fromDateTime(end);

      // Existing photo paths
      _bbFrontPath = a.bluebookFrontPath;
      _bbBackPath = a.bluebookBackPath;
      _bbOwnerPath = a.bluebookOwnerPath;
      _vFrontPath = a.vehicleFrontPath;
      _vBackPath = a.vehicleBackPath;
      _vRightPath = a.vehicleRightPath;
      _vLeftPath = a.vehicleLeftPath;
      _odoPath = a.odometerPath;
    }
  }

  @override
  void dispose() {
    _customModelController.dispose();
    _lotNumberController.dispose();
    _regNumberController.dispose();
    _kmRunController.dispose();
    _ownersCountController.dispose();
    _customColourController.dispose();
    _engineCapacityCcController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _incrementController.dispose();
    _reopenMinutesController.dispose();
    super.dispose();
  }

  // Dependent dropdown handlers
  void _onVehicleTypeChanged(String? newType) {
    if (newType == null || newType == _vehicleType) return;
    setState(() {
      _vehicleType = newType;
      _selectedBrand = null; // Clear brand when vehicle type changes
      _selectedModel = null; // Clear model when vehicle type changes
    });
  }

  void _onBrandChanged(String? newBrand) {
    if (newBrand == _selectedBrand) return;
    setState(() {
      _selectedBrand = newBrand;
      _selectedModel = null; // Clear model when brand changes
    });
  }

  void _onFuelTypeChanged(String? newFuel) {
    if (newFuel == null || newFuel == _fuelType) return;
    setState(() {
      _fuelType = newFuel;
      if (_fuelType == 'EV') {
        _engineOpened = null; // Hide & save null for EV
        _engineCapacityCcController.clear();
      } else {
        _engineOpened = 'No';
      }
    });
  }

  Future<void> _pickPhoto(String key, ImageSource source) async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 85);
    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    setState(() {
      switch (key) {
        case 'bb_front': _bbFrontBytes = bytes; break;
        case 'bb_back': _bbBackBytes = bytes; break;
        case 'bb_owner': _bbOwnerBytes = bytes; break;
        case 'v_front': _vFrontBytes = bytes; break;
        case 'v_back': _vBackBytes = bytes; break;
        case 'v_right': _vRightBytes = bytes; break;
        case 'v_left': _vLeftBytes = bytes; break;
        case 'odo': _odoBytes = bytes; break;
      }
    });
  }

  void _showPhotoSourceSheet(String key, String title) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upload $title',
              style: const TextStyle(
                fontFamily: 'Inter',
                color: AppColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: const Text('Choose from Photo Gallery', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy)),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(key, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
              title: const Text('Take Photo with Camera', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy)),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(key, ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  DateTime _combineDateTime(DateTime date, TimeOfDay time) {
    return ServerTimeService.nepalToUtc(date, time);
  }

  Future<void> _handleFormSubmission() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackbar('Please fill in all required vehicle fields.', isError: true);
      return;
    }

    if (_selectedBrand == null) {
      _showSnackbar('Please select a Brand Name.', isError: true);
      return;
    }
    if (_selectedModel == null) {
      _showSnackbar('Please select a Model.', isError: true);
      return;
    }

    // Photo Validation (All 8 photos required)
    final bool hasBBFront = _bbFrontBytes != null || (_bbFrontPath != null && _bbFrontPath!.isNotEmpty);
    final bool hasBBBack = _bbBackBytes != null || (_bbBackPath != null && _bbBackPath!.isNotEmpty);
    final bool hasBBOwner = _bbOwnerBytes != null || (_bbOwnerPath != null && _bbOwnerPath!.isNotEmpty);
    final bool hasVFront = _vFrontBytes != null || (_vFrontPath != null && _vFrontPath!.isNotEmpty);
    final bool hasVBack = _vBackBytes != null || (_vBackPath != null && _vBackPath!.isNotEmpty);
    final bool hasVRight = _vRightBytes != null || (_vRightPath != null && _vRightPath!.isNotEmpty);
    final bool hasVLeft = _vLeftBytes != null || (_vLeftPath != null && _vLeftPath!.isNotEmpty);
    final bool hasOdo = _odoBytes != null || (_odoPath != null && _odoPath!.isNotEmpty);

    if (!hasBBFront || !hasBBBack || !hasBBOwner) {
      _showSnackbar('All 3 Blue Book pictures (Front, Back, Owner Details) are required.', isError: true);
      return;
    }
    if (!hasVFront || !hasVBack || !hasVRight || !hasVLeft) {
      _showSnackbar('All 4 Bike/Scooter pictures (Front, Back, Right, Left) are required.', isError: true);
      return;
    }
    if (!hasOdo) {
      _showSnackbar('Odometer photo is required.', isError: true);
      return;
    }

    final nowUtc = ServerTimeService().currentServerTime;
    final DateTime startAt = (widget.auction == null && _startImmediately)
        ? nowUtc.subtract(const Duration(minutes: 1))
        : _combineDateTime(_startDate, _startTime);
    final endAt = _combineDateTime(_endDate, _endTime);

    if (endAt.isBefore(startAt) || endAt.isAtSameMomentAs(startAt)) {
      _showSnackbar('Auction End Time must be strictly after Start Time.', isError: true);
      return;
    }

    final currentUser = _service.currentUser;
    if (!currentUser.canCreateAuctions) {
      _showSnackbar('Only Sellers / Dealers and Admins can create or update auctions.', isError: true);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _uploadProgressMessage = 'Uploading vehicle photos & documents...';
    });

    final List<String> newlyCreatedPrivatePaths = [];
    final List<String> newlyCreatedPublicPaths = [];

    try {
      // 1. Upload Private Blue Book Documents
      String finalBBFront = _bbFrontPath ?? '';
      if (_bbFrontBytes != null) {
        finalBBFront = await _service.uploadPrivateDocument(_bbFrontBytes!, 'bb_front.jpg');
        newlyCreatedPrivatePaths.add(finalBBFront);
      }

      String finalBBBack = _bbBackPath ?? '';
      if (_bbBackBytes != null) {
        finalBBBack = await _service.uploadPrivateDocument(_bbBackBytes!, 'bb_back.jpg');
        newlyCreatedPrivatePaths.add(finalBBBack);
      }

      String finalBBOwner = _bbOwnerPath ?? '';
      if (_bbOwnerBytes != null) {
        finalBBOwner = await _service.uploadPrivateDocument(_bbOwnerBytes!, 'bb_owner.jpg');
        newlyCreatedPrivatePaths.add(finalBBOwner);
      }

      // 2. Upload Public Vehicle & Odometer Photos
      String finalVFront = _vFrontPath ?? '';
      if (_vFrontBytes != null) {
        finalVFront = await _service.uploadPublicImage(_vFrontBytes!, 'v_front.jpg');
        newlyCreatedPublicPaths.add(finalVFront);
      }

      String finalVBack = _vBackPath ?? '';
      if (_vBackBytes != null) {
        finalVBack = await _service.uploadPublicImage(_vBackBytes!, 'v_back.jpg');
        newlyCreatedPublicPaths.add(finalVBack);
      }

      String finalVRight = _vRightPath ?? '';
      if (_vRightBytes != null) {
        finalVRight = await _service.uploadPublicImage(_vRightBytes!, 'v_right.jpg');
        newlyCreatedPublicPaths.add(finalVRight);
      }

      String finalVLeft = _vLeftPath ?? '';
      if (_vLeftBytes != null) {
        finalVLeft = await _service.uploadPublicImage(_vLeftBytes!, 'v_left.jpg');
        newlyCreatedPublicPaths.add(finalVLeft);
      }

      String finalOdo = _odoPath ?? '';
      if (_odoBytes != null) {
        finalOdo = await _service.uploadPublicImage(_odoBytes!, 'odometer.jpg');
        newlyCreatedPublicPaths.add(finalOdo);
      }

      final finalModelName = _selectedModel == 'Other'
          ? _customModelController.text.trim()
          : _selectedModel!;
      final finalColourName = _colour == 'Other'
          ? _customColourController.text.trim()
          : _colour;

      final generatedTitle = '$_builtYear $_selectedBrand $finalModelName ($_vehicleType)';

      setState(() => _uploadProgressMessage = 'Saving vehicle auction to database...');

      if (widget.auction != null) {
        await _service.updateVehicleAuction(
          auctionId: widget.auction!.id,
          title: generatedTitle,
          description: _descController.text.trim(),
          startingPrice: double.parse(_priceController.text.trim()),
          minIncrement: double.parse(_incrementController.text.trim()),
          startAt: startAt,
          endAt: endAt,
          reopenDurationMinutes: int.parse(_reopenMinutesController.text.trim()),
          vehicleType: _vehicleType,
          brandName: _selectedBrand!,
          model: finalModelName,
          builtYear: _builtYear,
          yearCalendar: _yearCalendar,
          lotNumber: _lotNumberController.text.trim(),
          registrationNumber: _regNumberController.text.trim(),
          kilometresRun: double.parse(_kmRunController.text.trim()),
          numberOfOwners: int.parse(_ownersCountController.text.trim()),
          fuelType: _fuelType,
          engineOpened: _fuelType == 'EV' ? null : _engineOpened,
          colour: finalColourName,
          engineCapacity: _fuelType == 'EV' ? null : double.parse(_engineCapacityCcController.text.trim()),
          taxStatus: _taxStatus,
          bluebookFrontPath: finalBBFront,
          bluebookBackPath: finalBBBack,
          bluebookOwnerPath: finalBBOwner,
          vehicleFrontPath: finalVFront,
          vehicleBackPath: finalVBack,
          vehicleRightPath: finalVRight,
          vehicleLeftPath: finalVLeft,
          odometerPath: finalOdo,
        );
      } else {
        await _service.createVehicleAuction(
          title: generatedTitle,
          description: _descController.text.trim(),
          startingPrice: double.parse(_priceController.text.trim()),
          minIncrement: double.parse(_incrementController.text.trim()),
          startAt: startAt,
          endAt: endAt,
          reopenDurationMinutes: int.parse(_reopenMinutesController.text.trim()),
          vehicleType: _vehicleType,
          brandName: _selectedBrand!,
          model: finalModelName,
          builtYear: _builtYear,
          yearCalendar: _yearCalendar,
          lotNumber: _lotNumberController.text.trim(),
          registrationNumber: _regNumberController.text.trim(),
          kilometresRun: double.parse(_kmRunController.text.trim()),
          numberOfOwners: int.parse(_ownersCountController.text.trim()),
          fuelType: _fuelType,
          engineOpened: _fuelType == 'EV' ? null : _engineOpened,
          colour: finalColourName,
          engineCapacity: _fuelType == 'EV' ? null : double.parse(_engineCapacityCcController.text.trim()),
          taxStatus: _taxStatus,
          bluebookFrontPath: finalBBFront,
          bluebookBackPath: finalBBBack,
          bluebookOwnerPath: finalBBOwner,
          vehicleFrontPath: finalVFront,
          vehicleBackPath: finalVBack,
          vehicleRightPath: finalVRight,
          vehicleLeftPath: finalVLeft,
          odometerPath: finalOdo,
        );
      }

      if (mounted) {
        _showSnackbar(
          widget.auction != null ? '✅ Vehicle auction updated successfully!' : '✅ Vehicle auction published successfully!',
          isError: false,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      // Safe cleanup on NEW creation failure only
      if (widget.auction == null) {
        await _service.deleteStorageFiles('bluebook-documents', newlyCreatedPrivatePaths);
        await _service.deleteStorageFiles('auction-images', newlyCreatedPublicPaths);
      }

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _uploadProgressMessage = null;
        });
        _showSnackbar(e.toString().replaceAll('Exception: ', ''), isError: true);
      }
    }
  }

  void _showSnackbar(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final availableBrands = VehicleData.getBrandsForType(_vehicleType);
    final availableModels = _selectedBrand != null
        ? VehicleData.getModelsForBrand(_vehicleType, _selectedBrand!)
        : <String>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.navy),
        title: Text(
          widget.auction != null ? 'Edit Vehicle Auction' : 'Create Vehicle Auction',
          style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_service.currentUser.canCreateAuctions) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Seller / Dealer Authorization Required: Only authorized Sellers, Dealers, and Admins can publish auctions.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: Color(0xFFB45309),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // SECTION 1: VEHICLE CLASSIFICATION
                  _buildSectionHeader('1. VEHICLE CLASSIFICATION'),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SwitchListTile(
                      title: const Text('List as Business Auction', style: TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Displays Verified Business badge and links to business profile', style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 12)),
                      value: _isBusinessAuction,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) => setState(() => _isBusinessAuction = val),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownField<String>(
                          label: 'Vehicle Type *',
                          value: _vehicleType,
                          items: VehicleData.vehicleTypes,
                          onChanged: _onVehicleTypeChanged,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildDropdownField<String>(
                    label: 'Brand Name *',
                    value: _selectedBrand,
                    hint: 'Select Brand',
                    items: availableBrands,
                    onChanged: _onBrandChanged,
                  ),
                  const SizedBox(height: 12),
                  _buildDropdownField<String>(
                    label: 'Model *',
                    value: _selectedModel,
                    hint: _selectedBrand == null ? 'Select Brand first' : 'Select Model',
                    items: availableModels,
                    onChanged: (val) => setState(() => _selectedModel = val),
                  ),
                  if (_selectedModel == 'Other') ...[
                    const SizedBox(height: 12),
                    _buildTextField(
                      _customModelController,
                      'Specify Custom Model *',
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Model name required' : null,
                    ),
                  ],
                  const SizedBox(height: 24),

                  // SECTION 2: REGISTRATION & HISTORY
                  _buildSectionHeader('2. REGISTRATION & VEHICLE HISTORY'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildDropdownField<int>(
                          label: 'Built Year *',
                          value: _builtYear,
                          items: List.generate(35, (i) => DateTime.now().year + 5 - i),
                          onChanged: (val) {
                            if (val != null) setState(() => _builtYear = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: _buildDropdownField<String>(
                          label: 'Calendar *',
                          value: _yearCalendar,
                          items: const ['BS', 'AD'],
                          onChanged: (val) {
                            if (val != null) setState(() => _yearCalendar = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _lotNumberController,
                          'Lot Number *',
                          hintText: 'e.g. Lot 145',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Lot number required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _regNumberController,
                          'Reg Number *',
                          hintText: 'e.g. Ba 2 Pa 1234',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Registration no. required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _kmRunController,
                          'Total KM Run *',
                          hintText: 'e.g. 15400',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'KM run required';
                            final val = double.tryParse(v.trim());
                            if (val == null || val < 0) return 'Must be >= 0';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _ownersCountController,
                          'Number of Owners *',
                          hintText: '1 = First Owner',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            final val = int.tryParse(v.trim());
                            if (val == null || val < 1) return 'Must be >= 1';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildDropdownField<String>(
                    label: 'Tax Status *',
                    value: _taxStatus,
                    items: VehicleData.taxStatuses,
                    onChanged: (val) {
                      if (val != null) setState(() => _taxStatus = val);
                    },
                  ),
                  const SizedBox(height: 24),

                  // SECTION 3: SPECIFICATIONS & POWERTRAIN
                  _buildSectionHeader('3. POWERTRAIN & SPECIFICATIONS'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownField<String>(
                          label: 'Fuel Type *',
                          value: _fuelType,
                          items: VehicleData.fuelTypes,
                          onChanged: _onFuelTypeChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDropdownField<String>(
                          label: 'Colour *',
                          value: _colour,
                          items: VehicleData.commonColours,
                          onChanged: (val) {
                            if (val != null) setState(() => _colour = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_colour == 'Other') ...[
                    const SizedBox(height: 12),
                    _buildTextField(
                      _customColourController,
                      'Specify Custom Colour *',
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Colour required' : null,
                    ),
                  ],

                  // PETROL ONLY ENGINE FIELDS
                  if (_fuelType == 'Petrol') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField<String>(
                            label: 'Engine Opened *',
                            value: _engineOpened,
                            items: const ['No', 'Yes'],
                            onChanged: (val) => setState(() => _engineOpened = val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            _engineCapacityCcController,
                            'Capacity (CC) *',
                            hintText: 'e.g. 150',
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (_fuelType != 'Petrol') return null;
                              if (v == null || v.trim().isEmpty) return 'CC required';
                              final val = double.tryParse(v.trim());
                              if (val == null || val <= 0) return 'Must be > 0 CC';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),

                  // SECTION 4: BLUE BOOK DOCUMENTS (PRIVATE & RESTRICTED)
                  _buildSectionHeader('4. BLUE BOOK DOCUMENTS (PRIVATE STORAGE)'),
                  const SizedBox(height: 4),
                  const Text(
                    '🔒 Stored in private bucket. Accessible ONLY to authorized Admin and Uploader.',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildPhotoUploadTile('bb_front', 'Blue Book Front *', _bbFrontBytes, _bbFrontPath)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPhotoUploadTile('bb_back', 'Blue Book Back *', _bbBackBytes, _bbBackPath)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPhotoUploadTile('bb_owner', 'Owner Details *', _bbOwnerBytes, _bbOwnerPath)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SECTION 5: VEHICLE PHOTOS (4 SIDES)
                  _buildSectionHeader('5. VEHICLE PHOTOS (4 SIDES REQUIRED)'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildPhotoUploadTile('v_front', 'Front View *', _vFrontBytes, _vFrontPath)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPhotoUploadTile('v_back', 'Back View *', _vBackBytes, _vBackPath)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildPhotoUploadTile('v_right', 'Right Side *', _vRightBytes, _vRightPath)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPhotoUploadTile('v_left', 'Left Side *', _vLeftBytes, _vLeftPath)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SECTION 6: ODOMETER PHOTO
                  _buildSectionHeader('6. ODOMETER PHOTO (REQUIRED)'),
                  const SizedBox(height: 12),
                  _buildPhotoUploadTile('odo', 'Odometer Photo *', _odoBytes, _odoPath, isFullWidth: true),
                  const SizedBox(height: 24),

                  // SECTION 7: PRICING & TIMING CONFIGURATION
                  _buildSectionHeader('7. PRICING & SERVER TIMING (NEPAL TIME - NPT)'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_filled, color: AppColors.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Timezone: Nepal Standard Time (UTC+05:45) • Current: ${ServerTimeService().formattedCurrentNepalTime}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _priceController,
                          'Starting Price (Rs.) *',
                          hintText: 'e.g. 150000',
                          keyboardType: TextInputType.number,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Starting price required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _incrementController,
                          'Min Increment (Rs.) *',
                          hintText: 'e.g. 5000',
                          keyboardType: TextInputType.number,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Min increment required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        'Start Auction Immediately',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        _startImmediately
                            ? 'Goes live immediately upon publishing'
                            : 'Scheduled: Auction will start at specified Start Date & Time below',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                      activeThumbColor: AppColors.primary,
                      value: _startImmediately,
                      onChanged: (val) {
                        setState(() {
                          _startImmediately = val;
                        });
                      },
                    ),
                  ),
                  if (!_startImmediately) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildPickerTile(
                            label: 'Start Date (NPT)',
                            value: dateFormat.format(_startDate),
                            icon: Icons.calendar_today,
                            onTap: () => _selectDate(true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildPickerTile(
                            label: 'Start Time (NPT)',
                            value: _startTime.format(context),
                            icon: Icons.access_time,
                            onTap: () => _selectTime(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPickerTile(
                          label: 'End Date (NPT)',
                          value: dateFormat.format(_endDate),
                          icon: Icons.calendar_today,
                          onTap: () => _selectDate(false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildPickerTile(
                          label: 'End Time (NPT)',
                          value: _endTime.format(context),
                          icon: Icons.access_time,
                          onTap: () => _selectTime(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _descController,
                    'Additional Notes / Condition Details (Optional)',
                    hintText: 'Full servicing history, minor scratch info, accessories included...',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(_reopenMinutesController, 'Optional Reopen Duration (Minutes)', keyboardType: TextInputType.number),
                  const SizedBox(height: 32),

                  // SUBMIT BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleFormSubmission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          : Text(
                              widget.auction != null ? 'UPDATE VEHICLE AUCTION' : 'PUBLISH VEHICLE AUCTION',
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // OVERLAY LOADING SPINNER
          if (_isSubmitting)
            Positioned.fill(
              child: Container(
                color: AppColors.navy.withValues(alpha: 0.7),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      _uploadProgressMessage ?? 'Processing vehicle submission...',
                      style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Inter',
        color: AppColors.navy,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T? value,
    String? hint,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: items.contains(value) ? value : null,
      onChanged: onChanged,
      dropdownColor: AppColors.cardBackground,
      style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
        labelStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText),
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      ),
      items: items.map((item) {
        return DropdownMenuItem<T>(
          value: item,
          child: Text(item.toString(), style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy)),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
        labelStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText),
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      ),
    );
  }

  Widget _buildPickerTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 10)),
                Text(value, style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoUploadTile(
    String key,
    String label,
    Uint8List? bytes,
    String? existingPath, {
    bool isFullWidth = false,
  }) {
    final bool hasImage = bytes != null || (existingPath != null && existingPath.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'Inter', color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showPhotoSourceSheet(key, label),
          child: Container(
            height: isFullWidth ? 140 : 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasImage ? AppColors.success : AppColors.border,
                width: hasImage ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: bytes != null
                        ? Image.memory(bytes, fit: BoxFit.cover)
                        : (existingPath != null && existingPath.isNotEmpty
                            ? (existingPath.startsWith('http')
                                ? Image.network(existingPath, fit: BoxFit.cover)
                                : Container(
                                    color: AppColors.background,
                                    child: const Center(
                                      child: Icon(Icons.lock_outlined, color: AppColors.navy, size: 28),
                                    ),
                                  ))
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 24),
                                  SizedBox(height: 4),
                                  Text(
                                    'Tap to Upload',
                                    style: TextStyle(fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 10),
                                  ),
                                ],
                              )),
                  ),
                  if (hasImage)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            switch (key) {
                              case 'bb_front': _bbFrontBytes = null; _bbFrontPath = null; break;
                              case 'bb_back': _bbBackBytes = null; _bbBackPath = null; break;
                              case 'bb_owner': _bbOwnerBytes = null; _bbOwnerPath = null; break;
                              case 'v_front': _vFrontBytes = null; _vFrontPath = null; break;
                              case 'v_back': _vBackBytes = null; _vBackPath = null; break;
                              case 'v_right': _vRightBytes = null; _vRightPath = null; break;
                              case 'v_left': _vLeftBytes = null; _vLeftPath = null; break;
                              case 'odo': _odoBytes = null; _odoPath = null; break;
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
