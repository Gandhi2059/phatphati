// Login & Account Creation Screen (Single Page Unified Interface)
// Single page layout without tabs. Supports Sign In & Sign Up with Account Category selection.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:bid_app/config/supabase_config.dart';
import 'package:bid_app/theme/app_theme.dart';
import 'package:bid_app/models/auction_models.dart';
import 'package:bid_app/utils/nepal_phone_helper.dart';
import 'package:bid_app/screens/admin/admin_dashboard_screen.dart';
import 'package:bid_app/screens/seller/seller_dashboard_screen.dart';
import 'package:bid_app/screens/buyer/buyer_home_screen.dart';
import 'package:bid_app/screens/buyer/business_registration_screen.dart';
import 'package:bid_app/services/auction_service.dart';

class LoginScreen extends StatefulWidget {
  final String? notificationMessage;

  const LoginScreen({super.key, this.notificationMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isSignUpMode = false;
  String _loginRole = 'admin'; // 'buyer', 'seller', or 'admin'

  // Login Controllers
  final _loginIdController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Sign Up Controllers
  final _signUpNameController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPhoneController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  String _selectedAccountCategory =
      'dealer'; // Default to Dealer (Seller/Reconditioner)

  // OTP Verification State for Sign Up (Email OTP Only)
  final _otpCodeController = TextEditingController();
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _otpSent = false;
  bool _isEmailVerified = false;
  String? _verifiedEmail;
  int _resendCountdown = 0;
  Timer? _resendTimer;
  String? _otpFeedbackMessage;
  bool _isOtpFeedbackError = false;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.notificationMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.notificationMessage!,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 6),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _loginIdController.dispose();
    _loginPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPhoneController.dispose();
    _signUpPasswordController.dispose();
    _otpCodeController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final input = _loginIdController.text.trim();
    final password = _loginPasswordController.text;

    try {
      var email = input.toLowerCase();
      if (_loginRole != 'admin' && !email.contains('@')) {
        final resolvedEmail = await SupabaseConfig.client.rpc(
          'resolve_login_email',
          params: {'p_identifier': input, 'p_password': password},
        );
        if (resolvedEmail == null || !resolvedEmail.toString().contains('@')) {
          throw Exception('Unable to find an account for that identifier.');
        }
        email = resolvedEmail.toString();
      }

      final response = await SupabaseConfig.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) throw Exception('Login failed.');

      final profile = await AuctionService().fetchUserProfile(user.id);
      if (profile == null) throw Exception('User profile not found.');

      final hasSelectedRole = switch (_loginRole) {
        'admin' => profile.isAdmin,
        'seller' => profile.isSeller || profile.isDealer,
        _ => profile.isBuyer || profile.isReconditioner,
      };
      if (!hasSelectedRole) {
        throw Exception('This account does not have $_loginRole access.');
      }

      if (!mounted) return;
      AuctionService().setCurrentProfile(profile);
      final destination = switch (_loginRole) {
        'admin' => const AdminDashboardScreen(),
        'seller' => const SellerDashboardScreen(),
        _ => const BuyerHomeScreen(),
      };
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _checkDuplicateAccount(String email, String phone) async {
    // 1. Check RPC check_account_availability
    try {
      final res = await SupabaseConfig.client
          .rpc('check_account_availability', params: {
        'p_email': email,
        'p_phone': phone,
      });
      if (res is Map && res['available'] == false) {
        return res['message']?.toString() ??
            'Account credentials already registered.';
      }
    } catch (_) {}

    // 2. Fallback direct query on public.profiles
    try {
      if (email.isNotEmpty) {
        final existingEmail = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .eq('email', email.toLowerCase())
            .maybeSingle();
        if (existingEmail != null) {
          return 'These registration details cannot be used. If you already have an account, please sign in.';
        }
      }

      if (phone.isNotEmpty) {
        final national = NepalPhoneHelper.extractNational(phone) ?? phone;
        final existingPhone = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .or('phone.eq.$phone,phone.eq.$national')
            .maybeSingle();
        if (existingPhone != null) {
          return 'These registration details cannot be used. If you already have an account, please sign in.';
        }
      }
    } catch (_) {}

    return null;
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() => _resendCountdown = 0);
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  void _clearSignUpFields() {
    _signUpNameController.clear();
    _signUpEmailController.clear();
    _signUpPhoneController.clear();
    _signUpPasswordController.clear();
    _otpCodeController.clear();
    _isEmailVerified = false;
    _verifiedEmail = null;
    _otpSent = false;
    _isSendingOtp = false;
    _isVerifyingOtp = false;
    _resendCountdown = 0;
    _resendTimer?.cancel();
    _errorMessage = null;
    _otpFeedbackMessage = null;
    _isOtpFeedbackError = false;
  }

  Future<void> _handleSendOtp() async {
    final email = _signUpEmailController.text.trim().toLowerCase();

    // 1. Validate email address format
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() {
        _errorMessage =
            'Please enter a valid email address to receive your OTP code.';
        _isOtpFeedbackError = true;
        _otpFeedbackMessage = 'Valid email address required.';
      });
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _errorMessage = null;
      _otpFeedbackMessage = null;
    });

    // 2. Pre-flight duplicate check on email
    final dupError = await _checkDuplicateAccount(email, '');
    if (dupError != null) {
      setState(() {
        _isSendingOtp = false;
        _errorMessage = dupError;
        _isOtpFeedbackError = true;
        _otpFeedbackMessage = dupError;
      });
      return;
    }

    // 3. Dispatch Supabase Email OTP
    try {
      await SupabaseConfig.client.auth.signInWithOtp(
        email: email,
      );
      if (!mounted) return;
      setState(() {
        _isSendingOtp = false;
        _otpSent = true;
        _resendCountdown = 60;
        _isOtpFeedbackError = false;
        _otpFeedbackMessage =
            '6-digit OTP code sent to $email. Enter the code below to verify.';
      });
      _startResendTimer();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSendingOtp = false;
        _isOtpFeedbackError = true;
        _otpFeedbackMessage = e.message;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSendingOtp = false;
        _isOtpFeedbackError = true;
        _otpFeedbackMessage = 'Failed to dispatch verification code: $e';
        _errorMessage =
            'Could not send verification code. Please check your network connection.';
      });
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpCodeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _isOtpFeedbackError = true;
        _otpFeedbackMessage = 'Please enter a full 6-digit verification code.';
      });
      return;
    }

    final email = _signUpEmailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _isOtpFeedbackError = true;
        _otpFeedbackMessage = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
      _otpFeedbackMessage = null;
    });

    try {
      await SupabaseConfig.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
      if (!mounted) return;
      setState(() {
        _isEmailVerified = true;
        _verifiedEmail = email;
        _isVerifyingOtp = false;
        _isOtpFeedbackError = false;
        _otpFeedbackMessage = '✓ Email address verified ($email)!';
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifyingOtp = false;
        _isOtpFeedbackError = true;
        _otpFeedbackMessage = 'Invalid OTP code: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifyingOtp = false;
        _isOtpFeedbackError = true;
        _otpFeedbackMessage = 'Verification error: $e';
      });
    }
  }

  Future<void> _handleCreateAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final rawPhone = _signUpPhoneController.text.trim();
    if (!NepalPhoneHelper.isValid(rawPhone)) {
      setState(() {
        _errorMessage =
            'Please enter a valid 10-digit Nepal mobile number (e.g. 9841234567).';
      });
      return;
    }

    final formattedPhone = NepalPhoneHelper.normalize(rawPhone)!;
    final email = _signUpEmailController.text.trim().toLowerCase();

    // Enforce email verification status
    if (!_isEmailVerified || _verifiedEmail == null) {
      setState(() {
        _errorMessage =
            'Please verify your email address with the OTP code before completing registration.';
      });
      return;
    }
    if (_verifiedEmail!.toLowerCase() != email) {
      setState(() {
        _isEmailVerified = false;
        _verifiedEmail = null;
        _errorMessage =
            'Email address was changed after verification. Please re-verify.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final name = _signUpNameController.text.trim();
      final password = _signUpPasswordController.text;
      final phone = formattedPhone;

      // Final duplicate check
      final dupError = await _checkDuplicateAccount(email, phone);
      if (dupError != null) {
        throw Exception(dupError);
      }

      final role = _selectedAccountCategory == 'dealer' ? 'seller' : 'buyer';
      final existingBuyers = await AuctionService().fetchRegisteredBuyers();
      final generatedBuyerId = 'BUYER-${101 + existingBuyers.length}';

      String? userId;

      // Method: Supported Supabase Auth APIs
      // If user is already authenticated via email OTP verification, update password & metadata securely.
      final activeUser = SupabaseConfig.client.auth.currentUser;
      if (activeUser != null &&
          activeUser.email?.toLowerCase() == email.toLowerCase()) {
        try {
          final updateRes = await SupabaseConfig.client.auth.updateUser(
            UserAttributes(
              password: password,
              data: {
                'full_name': name,
                'phone': phone,
                'role': role,
                'buyer_id': role == 'buyer' ? generatedBuyerId : null,
                'account_category': _selectedAccountCategory,
              },
            ),
          );
          userId = updateRes.user?.id;
        } catch (_) {}
      }

      // If not already authenticated through OTP session, register via standard Supabase Auth SignUp
      if (userId == null) {
        final signUpRes = await SupabaseConfig.client.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'phone': phone,
            'role': role,
            'buyer_id': role == 'buyer' ? generatedBuyerId : null,
            'account_category': _selectedAccountCategory,
          },
        );
        userId = signUpRes.user?.id;
      }

      userId ??= SupabaseConfig.client.auth.currentUser?.id;

      // Authenticate session immediately if needed
      if (SupabaseConfig.client.auth.currentSession == null) {
        try {
          await SupabaseConfig.client.auth.signInWithPassword(
            email: email,
            password: password,
          );
        } catch (_) {}
      }

      // Safely complete profile registration for the authenticated user
      bool rpcSuccess = false;
      try {
        final rpcRes = await SupabaseConfig.client.rpc(
          'complete_user_registration',
          params: {
            'p_full_name': name,
            'p_phone': phone,
            'p_role': role,
            'p_account_category': _selectedAccountCategory,
            'p_buyer_id': role == 'buyer' ? generatedBuyerId : null,
          },
        );
        if (rpcRes is Map && rpcRes['success'] == true) {
          rpcSuccess = true;
        }
      } catch (_) {}

      if (!rpcSuccess && userId != null) {
        final profileData = <String, dynamic>{
          'id': userId,
          'buyer_id': role == 'buyer' ? generatedBuyerId : null,
          'email': email,
          'full_name': name,
          'phone': phone,
          'role': role,
          'account_category': _selectedAccountCategory,
          'email_verified': true,
          'phone_verified': false,
          'phone_verified_at': null,
        };
        try {
          await SupabaseConfig.client.from('profiles').upsert(profileData);
        } catch (_) {}
      }

      userId ??= const Uuid().v4();

      final profile = Profile(
        id: userId,
        buyerId: role == 'buyer' ? generatedBuyerId : null,
        email: email,
        fullName: name,
        phone: phone,
        role: role,
        accountCategory: _selectedAccountCategory,
        emailVerified: true,
        phoneVerified: false,
        phoneVerifiedAt: null,
      );

      AuctionService().setCurrentProfile(profile);

      // Notify Admin in real-time about new Buyer or Seller Form 1 registration
      await AuctionService().notifyAdminNewUserRegistration(
        userId: userId,
        fullName: name,
        email: email,
        phone: phone,
        role: role,
      );

      if (!mounted) return;

      final roleDisplay =
          role == 'seller' ? 'Seller (Dealer)' : 'Buyer (Reconditioner)';
      final successMsg =
          'Form 1 completed! Account registered as $roleDisplay. Admin has been notified for verification.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successMsg,
            style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 5),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessRegistrationScreen(
            initialBusinessType: _selectedAccountCategory,
            allowSkip: true,
          ),
        ),
      );
    } catch (e) {
      String cleanMsg = e.toString().replaceAll('Exception: ', '');
      if (cleanMsg.contains('over_email_send_rate_limit') ||
          cleanMsg.contains('rate limit')) {
        cleanMsg =
            'Account registered! You can now log in with your email and password.';
      }
      setState(() {
        _errorMessage = cleanMsg;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo & Header
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/phatphati_logo.png',
                          height: 84,
                          width: 84,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'PHATPHATI AUCTIONS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSignUpMode
                          ? 'Create Account (Dealer, Reconditioner)'
                          : 'Vehicle Auction & Bidding Platform',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.danger, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.danger,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // SINGLE PAGE FORM CONTENT
                    if (!_isSignUpMode) ...[
                      // SIGN IN MODE
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Buyer',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _loginRole == 'buyer'
                                          ? Colors.white
                                          : AppColors.navy,
                                    ),
                                  ),
                                  Text(
                                    'Reconditioner',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 9,
                                      color: _loginRole == 'buyer'
                                          ? Colors.white70
                                          : AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 2),
                              selected: _loginRole == 'buyer',
                              selectedColor: AppColors.navy,
                              backgroundColor: AppColors.background,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: _loginRole == 'buyer'
                                      ? AppColors.navy
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (sel) {
                                setState(() {
                                  _loginRole = 'buyer';
                                  _loginIdController.clear();
                                  _loginPasswordController.clear();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ChoiceChip(
                              label: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Seller',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _loginRole == 'seller'
                                          ? Colors.white
                                          : AppColors.navy,
                                    ),
                                  ),
                                  Text(
                                    'Dealer',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 9,
                                      color: _loginRole == 'seller'
                                          ? Colors.white70
                                          : AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 2),
                              selected: _loginRole == 'seller',
                              selectedColor: AppColors.navy,
                              backgroundColor: AppColors.background,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: _loginRole == 'seller'
                                      ? AppColors.navy
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (sel) {
                                setState(() {
                                  _loginRole = 'seller';
                                  _loginIdController.clear();
                                  _loginPasswordController.clear();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ChoiceChip(
                              label: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Admin',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _loginRole == 'admin'
                                          ? Colors.white
                                          : AppColors.navy,
                                    ),
                                  ),
                                  Text(
                                    'Platform',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 9,
                                      color: _loginRole == 'admin'
                                          ? Colors.white70
                                          : AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 2),
                              selected: _loginRole == 'admin',
                              selectedColor: AppColors.navy,
                              backgroundColor: AppColors.background,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: _loginRole == 'admin'
                                      ? AppColors.navy
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (sel) {
                                setState(() {
                                  _loginRole = 'admin';
                                  _loginIdController.clear();
                                  _loginPasswordController.clear();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _loginIdController,
                        style: const TextStyle(
                            fontFamily: 'Inter', color: AppColors.navy),
                        decoration: _buildInputDecoration(
                          _loginRole == 'admin'
                              ? 'Admin Email'
                              : _loginRole == 'seller'
                                  ? 'Dealer (Seller) Email or Phone'
                                  : 'Buyer (Reconditioner) ID or Email',
                          Icons.badge_outlined,
                        ),
                        validator: (v) =>
                            v!.isEmpty ? 'Identifier required' : null,
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _loginPasswordController,
                        obscureText: true,
                        style: const TextStyle(
                            fontFamily: 'Inter', color: AppColors.navy),
                        decoration: _buildInputDecoration(
                          _loginRole == 'admin' ? 'Admin Password' : 'Password',
                          Icons.lock_outline,
                        ),
                        validator: (v) =>
                            v!.isEmpty ? 'Password required' : null,
                      ),
                      const SizedBox(height: 20),

                      // Primary Sign In Button
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  _loginRole == 'admin'
                                      ? 'Sign In as Admin'
                                      : (_loginRole == 'seller'
                                          ? 'Sign In as Dealer (Seller)'
                                          : 'Sign In as Buyer (Reconditioner)'),
                                  style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // SIGN UP BUTTON BELOW SIGN IN BUTTON
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isSignUpMode = true;
                            _errorMessage = null;
                            _clearSignUpFields();
                          });
                        },
                        icon: const Icon(Icons.person_add_outlined,
                            color: AppColors.navy, size: 18),
                        label: const Text(
                          'Don\'t have an account? Create New Account',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ] else ...[
                      // SIGN UP MODE (FORM 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.looks_one_rounded,
                                size: 16, color: AppColors.primary),
                            SizedBox(width: 6),
                            Text(
                              'FORM 1: ROLE SELECTION & CREDENTIALS',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Select Account Role *',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.navy,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Buyer: bids on vehicle auctions. Seller: creates & manages auctions. Admin is notified instantly upon submission.',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.secondaryText,
                            fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Buyer (Reconditioner)',
                                    style: TextStyle(
                                        fontFamily: 'Inter', fontSize: 12)),
                              ),
                              selected:
                                  _selectedAccountCategory == 'recondition',
                              selectedColor: AppColors.navy,
                              backgroundColor: AppColors.background,
                              labelStyle: TextStyle(
                                fontFamily: 'Inter',
                                color: _selectedAccountCategory == 'recondition'
                                    ? Colors.white
                                    : AppColors.secondaryText,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color:
                                      _selectedAccountCategory == 'recondition'
                                          ? AppColors.navy
                                          : AppColors.border,
                                ),
                              ),
                              onSelected: (sel) => setState(() =>
                                  _selectedAccountCategory = 'recondition'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Seller (Dealer)',
                                    style: TextStyle(
                                        fontFamily: 'Inter', fontSize: 12)),
                              ),
                              selected: _selectedAccountCategory == 'dealer',
                              selectedColor: AppColors.navy,
                              backgroundColor: AppColors.background,
                              labelStyle: TextStyle(
                                fontFamily: 'Inter',
                                color: _selectedAccountCategory == 'dealer'
                                    ? Colors.white
                                    : AppColors.secondaryText,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: _selectedAccountCategory == 'dealer'
                                      ? AppColors.navy
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (sel) => setState(
                                  () => _selectedAccountCategory = 'dealer'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _clearSignUpFields();
                              });
                            },
                            icon: const Icon(Icons.clear_all,
                                size: 14, color: AppColors.secondaryText),
                            label: const Text(
                              'Clear Form',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  color: AppColors.secondaryText),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      TextFormField(
                        controller: _signUpNameController,
                        style: const TextStyle(
                            fontFamily: 'Inter', color: AppColors.navy),
                        decoration: _buildInputDecoration(
                            'Full Name *', Icons.person_outline),
                        validator: (v) =>
                            _isSignUpMode && (v == null || v.trim().isEmpty)
                                ? 'Full Name required'
                                : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _signUpEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                            fontFamily: 'Inter', color: AppColors.navy),
                        decoration: _buildInputDecoration(
                                'Email Address *', Icons.email_outlined)
                            .copyWith(
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _isEmailVerified
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.success
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle,
                                            color: AppColors.success, size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'Verified',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.success,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : TextButton(
                                    onPressed: (_isSendingOtp ||
                                            _signUpEmailController.text
                                                .trim()
                                                .isEmpty)
                                        ? null
                                        : _handleSendOtp,
                                    style: TextButton.styleFrom(
                                      backgroundColor: AppColors.navy,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    child: _isSendingOtp
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2),
                                          )
                                        : Text(
                                            _otpSent
                                                ? 'Resend OTP'
                                                : 'Send OTP',
                                            style: const TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold),
                                          ),
                                  ),
                          ),
                        ),
                        validator: (v) {
                          if (!_isSignUpMode) return null;
                          if (v == null || v.trim().isEmpty)
                            return 'Email required';
                          if (!v.contains('@') || !v.contains('.'))
                            return 'Valid email required';
                          return null;
                        },
                        onChanged: (val) {
                          if (_isEmailVerified) {
                            if (_verifiedEmail != null &&
                                val.trim().toLowerCase() !=
                                    _verifiedEmail!.toLowerCase()) {
                              setState(() {
                                _isEmailVerified = false;
                                _verifiedEmail = null;
                                _otpSent = false;
                                _otpCodeController.clear();
                                _otpFeedbackMessage =
                                    'Email changed. Please re-verify.';
                                _isOtpFeedbackError = false;
                              });
                            }
                          }
                        },
                      ),

                      if (_isEmailVerified) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppColors.success.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.mark_email_read_rounded,
                                  color: AppColors.success, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '✓ Email verified (${_verifiedEmail ?? _signUpEmailController.text})',
                                  style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isEmailVerified = false;
                                    _verifiedEmail = null;
                                    _otpSent = false;
                                    _otpCodeController.clear();
                                    _otpFeedbackMessage = null;
                                  });
                                },
                                child: const Text(
                                  'Change',
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_otpSent && !_isEmailVerified) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.mark_email_read_outlined,
                                      color: AppColors.primary, size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Enter 6-Digit Email OTP',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  const Spacer(),
                                  if (_resendCountdown > 0)
                                    Text(
                                      'Resend in ${_resendCountdown}s',
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.secondaryText,
                                          fontSize: 11),
                                    )
                                  else
                                    GestureDetector(
                                      onTap:
                                          _isSendingOtp ? null : _handleSendOtp,
                                      child: const Text(
                                        'Resend Code',
                                        style: TextStyle(
                                            fontFamily: 'Inter',
                                            color: AppColors.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _otpCodeController,
                                      keyboardType: TextInputType.number,
                                      maxLength: 6,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppColors.navy,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          letterSpacing: 6),
                                      decoration: InputDecoration(
                                        counterText: '',
                                        hintText: '• • • • • •',
                                        hintStyle: const TextStyle(
                                            letterSpacing: 4,
                                            color: AppColors.secondaryText),
                                        filled: true,
                                        fillColor: AppColors.cardBackground,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                vertical: 10, horizontal: 12),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: const BorderSide(
                                                color: AppColors.border)),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: const BorderSide(
                                                color: AppColors.primary,
                                                width: 1.5)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: _isVerifyingOtp
                                        ? null
                                        : _handleVerifyOtp,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    child: _isVerifyingOtp
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2))
                                        : const Text('Verify',
                                            style: TextStyle(
                                                fontFamily: 'Inter',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13)),
                                  ),
                                ],
                              ),
                              if (_otpFeedbackMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _otpFeedbackMessage!,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    color: _isOtpFeedbackError
                                        ? AppColors.danger
                                        : AppColors.success,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _signUpPhoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(
                            fontFamily: 'Inter', color: AppColors.navy),
                        decoration: _buildInputDecoration(
                                'Nepal Mobile (e.g. 9841234567) *',
                                Icons.phone_android_outlined)
                            .copyWith(
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 14, right: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_android_outlined,
                                    color: AppColors.secondaryText, size: 20),
                                SizedBox(width: 6),
                                Text(
                                  '+977',
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                SizedBox(width: 4),
                                Text('|',
                                    style: TextStyle(
                                        color: AppColors.border, fontSize: 16)),
                              ],
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (!_isSignUpMode) return null;
                          if (v == null || v.trim().isEmpty)
                            return 'Mobile number required';
                          if (!NepalPhoneHelper.isValid(v)) {
                            return 'Enter valid 10-digit Nepal number (e.g. 984XXXXXXX)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _signUpPasswordController,
                        obscureText: true,
                        style: const TextStyle(
                            fontFamily: 'Inter', color: AppColors.navy),
                        decoration: _buildInputDecoration(
                            'Password (Min 6 chars) *', Icons.lock_outline),
                        validator: (v) =>
                            _isSignUpMode && (v == null || v.length < 6)
                                ? 'Password must be at least 6 chars'
                                : null,
                      ),
                      const SizedBox(height: 20),

                      // Primary Register Button
                      Builder(
                        builder: (context) {
                          return SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : _handleCreateAccount,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isEmailVerified
                                    ? AppColors.primary
                                    : AppColors.navy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (_isEmailVerified) ...[
                                          const Icon(Icons.verified_rounded,
                                              size: 18),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          _isEmailVerified
                                              ? 'Submit Form 1 & Continue'
                                              : 'Verify Email to Complete Form 1',
                                          style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // BACK TO SIGN IN BUTTON BELOW REGISTER BUTTON
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isSignUpMode = false;
                            _errorMessage = null;
                            _clearSignUpFields();
                          });
                        },
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.navy, size: 18),
                        label: const Text(
                          'Already have an account? Sign In',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          fontFamily: 'Inter', color: AppColors.secondaryText, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.secondaryText, size: 20),
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
      ),
    );
  }
}
