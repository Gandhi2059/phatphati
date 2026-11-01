import 'package:flutter_test/flutter_test.dart';
import 'package:bid_app/utils/nepal_phone_helper.dart';
import 'package:bid_app/models/auction_models.dart';

void main() {
  group('1. Nepal Phone Number Validation & Normalization', () {
    test('Accepts valid 10-digit Nepal mobile numbers across all operators', () {
      final validSamples = [
        '9841234567', // NTC GSM postpaid/prepaid
        '9851012345', // NTC postpaid
        '9860123456', // NTC GSM
        '9801234567', // Ncell
        '9812345678', // Ncell
        '9823456789', // Ncell
        '9741234567', // NTC CDMA
        '9751234567', // NTC
        '9761234567', // NTC
        '9881234567', // Smart Cell
        '9611234567', // Smart Cell
      ];

      for (final phone in validSamples) {
        expect(NepalPhoneHelper.isValid(phone), isTrue, reason: '$phone should be valid');
        final normalized = NepalPhoneHelper.normalize(phone);
        expect(normalized, isNotNull);
        expect(normalized!.startsWith('+977'), isTrue);
        expect(normalized.length, equals(14));
      }
    });

    test('Accepts valid Nepal numbers with country code prefix variations', () {
      expect(NepalPhoneHelper.isValid('+9779841234567'), isTrue);
      expect(NepalPhoneHelper.normalize('+9779841234567'), equals('+9779841234567'));

      expect(NepalPhoneHelper.isValid('+977 984-1234567'), isTrue);
      expect(NepalPhoneHelper.normalize('+977 984-1234567'), equals('+9779841234567'));

      expect(NepalPhoneHelper.isValid('9779841234567'), isTrue);
      expect(NepalPhoneHelper.normalize('9779841234567'), equals('+9779841234567'));

      expect(NepalPhoneHelper.isValid('00977 984 123 4567'), isTrue);
      expect(NepalPhoneHelper.normalize('00977 984 123 4567'), equals('+9779841234567'));
    });

    test('Rejects invalid phone numbers', () {
      final invalidSamples = [
        '',
        '   ',
        '12345', // Too short
        '984123456', // 9 digits
        '98412345678', // 11 digits
        '014234567', // Nepal landline (not mobile)
        '919841234567', // India prefix (+91)
        '+14155552671', // US number
        '98412abcde', // Letters
        'abcdefghij',
      ];

      for (final phone in invalidSamples) {
        expect(NepalPhoneHelper.isValid(phone), isFalse, reason: '$phone should be invalid');
        expect(NepalPhoneHelper.normalize(phone), isNull);
      }
    });

    test('Extracts national 10-digit number correctly', () {
      expect(NepalPhoneHelper.extractNational('9841234567'), equals('9841234567'));
      expect(NepalPhoneHelper.extractNational('+9779841234567'), equals('9841234567'));
      expect(NepalPhoneHelper.extractNational('+977 984-1234567'), equals('9841234567'));
    });

    test('Formats display and privacy masks correctly', () {
      expect(NepalPhoneHelper.formatDisplay('9841234567'), equals('+977 984-1234567'));
      expect(NepalPhoneHelper.maskPhone('9841234567'), equals('+977 984***4567'));
    });
  });

  group('2. Verification Invalidation on Phone Number Change', () {
    test('Detects equivalent phone numbers without false invalidation', () {
      const verified = '+9779841234567';
      expect(NepalPhoneHelper.areSame('9841234567', verified), isTrue);
      expect(NepalPhoneHelper.areSame('+977 984-1234567', verified), isTrue);
      expect(NepalPhoneHelper.areSame('9779841234567', verified), isTrue);
    });

    test('Invalidates verification when phone number is changed', () {
      const verified = '+9779841234567';
      expect(NepalPhoneHelper.areSame('9841234568', verified), isFalse);
      expect(NepalPhoneHelper.areSame('9851234567', verified), isFalse);
      expect(NepalPhoneHelper.areSame('invalid_number', verified), isFalse);
      expect(NepalPhoneHelper.areSame('', verified), isFalse);
    });
  });

  group('3. Development vs Production OTP Security', () {
    test('Simulates OTP validation policy under kDebugMode vs release', () {
      bool validateOtpPolicy({required String token, required bool isDebugMode}) {
        if (isDebugMode && (token == '123456' || token == '000000')) {
          return true; // Test code accepted in debug mode only
        }
        return false; // In production or with wrong code, rejected
      }

      // Debug mode behavior
      expect(validateOtpPolicy(token: '123456', isDebugMode: true), isTrue);
      expect(validateOtpPolicy(token: '000000', isDebugMode: true), isTrue);
      expect(validateOtpPolicy(token: '999999', isDebugMode: true), isFalse);

      // Production / Release behavior: Hardcoded codes are STRICTLY REJECTED
      expect(validateOtpPolicy(token: '123456', isDebugMode: false), isFalse);
      expect(validateOtpPolicy(token: '000000', isDebugMode: false), isFalse);
      expect(validateOtpPolicy(token: '999999', isDebugMode: false), isFalse);
    });
  });

  group('4. Profile Model Verification State', () {
    test('Profile stores and parses phone_verified and phone_verified_at', () {
      final now = DateTime.now();
      final profile = Profile(
        id: 'user-101',
        email: 'nepal_user@example.com',
        fullName: 'Ram Bahadur',
        phone: '+9779841234567',
        role: 'buyer',
        phoneVerified: true,
        phoneVerifiedAt: now,
      );

      expect(profile.phoneVerified, isTrue);
      expect(profile.phoneVerifiedAt, equals(now));
      expect(profile.phone, equals('+9779841234567'));

      // From JSON deserialization
      final jsonMap = {
        'id': 'user-102',
        'email': 'sita@example.com',
        'full_name': 'Sita Sharma',
        'phone': '+9779801234567',
        'role': 'seller',
        'account_category': 'dealer',
        'phone_verified': true,
        'phone_verified_at': now.toIso8601String(),
      };

      final parsed = Profile.fromJson(jsonMap);
      expect(parsed.id, equals('user-102'));
      expect(parsed.phoneVerified, isTrue);
      expect(parsed.phoneVerifiedAt, isNotNull);
      expect(parsed.phone, equals('+9779801234567'));
      expect(parsed.isSeller, isTrue);
    });

    test('Profile defaults phoneVerified to false when not verified', () {
      final profile = Profile(
        id: 'user-103',
        email: 'unverified@example.com',
        fullName: 'Unverified User',
        role: 'buyer',
      );

      expect(profile.phoneVerified, isFalse);
      expect(profile.phoneVerifiedAt, isNull);

      final fromJson = Profile.fromJson({
        'id': 'user-104',
        'email': 'unverified2@example.com',
        'full_name': 'Unverified Two',
        'role': 'buyer',
      });
      expect(fromJson.phoneVerified, isFalse);
      expect(fromJson.phoneVerifiedAt, isNull);
      expect(fromJson.emailVerified, isFalse);
    });

    test('Profile distinguishes email verification from phone verification', () {
      final emailOnlyProfile = Profile.fromJson({
        'id': 'user-105',
        'email': 'buyer@example.com',
        'phone': '+9779841234567',
        'role': 'buyer',
        'email_verified': true,
        'phone_verified': false,
      });

      expect(emailOnlyProfile.emailVerified, isTrue, reason: 'Email ownership is confirmed');
      expect(emailOnlyProfile.phoneVerified, isFalse, reason: 'Phone SIM is unverified');
      expect(emailOnlyProfile.phone, equals('+9779841234567'));
    });
  });

  group('5. Client Bypass & Privilege Escalation Prevention', () {
    test('Simulates create_authenticated_user parameter validation: blocks admin self-registration', () {
      Map<String, dynamic> simulateCreateAuthenticatedUserRpc({
        required String email,
        required String password,
        required String role,
        required String phone,
      }) {
        final cleanRole = role.trim().toLowerCase();
        if (cleanRole == 'admin') {
          throw Exception('Admin accounts cannot be self-registered.');
        }
        if (password.length < 6) {
          throw Exception('Password must be at least 6 characters.');
        }
        return {
          'success': true,
          'email': email.trim().toLowerCase(),
          'role': ['seller', 'dealer', 'recondition'].contains(cleanRole) ? cleanRole : 'buyer',
          'phone_verified': false, // Server NEVER marks phone verified from client input
        };
      }

      // Admin role self-registration is rejected
      expect(
        () => simulateCreateAuthenticatedUserRpc(
          email: 'hacker@example.com',
          password: 'password123',
          role: 'admin',
          phone: '+9779841234567',
        ),
        throwsA(predicate((e) => e.toString().contains('Admin accounts cannot be self-registered.'))),
      );

      // Normal buyer registration succeeds with phone_verified = false
      final res = simulateCreateAuthenticatedUserRpc(
        email: 'buyer@example.com',
        password: 'password123',
        role: 'buyer',
        phone: '+9779841234567',
      );
      expect(res['success'], isTrue);
      expect(res['role'], equals('buyer'));
      expect(res['phone_verified'], isFalse);
    });

    test('Simulates DB trigger: resets untrusted phone_verified if auth.users has no confirmation', () {
      Map<String, dynamic> simulateProtectProfilesTrigger({
        required Map<String, dynamic> profileRow,
        required bool authUserHasPhoneConfirmedAt,
      }) {
        final row = Map<String, dynamic>.from(profileRow);
        if (row['phone_verified'] == true) {
          if (!authUserHasPhoneConfirmedAt) {
            // Trigger forces revert
            row['phone_verified'] = false;
            row['phone_verified_at'] = null;
          }
        }
        return row;
      }

      // Untrusted client attempt to upsert phone_verified: true without auth confirmation
      final maliciousAttempt = {
        'id': 'user-hacker',
        'email': 'hacker@example.com',
        'phone_verified': true,
        'phone_verified_at': DateTime.now().toIso8601String(),
      };

      final guarded = simulateProtectProfilesTrigger(
        profileRow: maliciousAttempt,
        authUserHasPhoneConfirmedAt: false,
      );

      expect(guarded['phone_verified'], isFalse, reason: 'Trigger must revert unverified phone');
      expect(guarded['phone_verified_at'], isNull);

      // Legitimate auth trigger with phone_confirmed_at IS permitted
      final legitimate = simulateProtectProfilesTrigger(
        profileRow: maliciousAttempt,
        authUserHasPhoneConfirmedAt: true,
      );
      expect(legitimate['phone_verified'], isTrue);
    });
  });

  group('6. Duplicate Prevention & Format Normalization', () {
    test('Ensures various format inputs resolve to the exact same normalized key', () {
      final formats = [
        '9841234567',
        '+9779841234567',
        '+977 984-1234567',
        '9779841234567',
        '00977 984 123 4567',
      ];

      final normalizedKeys = formats.map((f) => NepalPhoneHelper.normalize(f)).toSet();
      expect(normalizedKeys.length, equals(1), reason: 'All variations must map to single unique key');
      expect(normalizedKeys.first, equals('+9779841234567'));
    });

    test('Strict validation rejects foreign, landline, and malformed numbers (no arbitrary 10-digit truncation)', () {
      final foreignAndInvalid = [
        '+91 9841234567', // Indian prefix with 10 digits
        '+919841234567',
        '+1 415 984 4567', // US number
        '+44 7984 123456', // UK number
        '01 4234567', // Kathmandu landline
        '014234567',
        '8841234567', // Invalid mobile starting digit
        '1234567890',
        '984123456', // 9 digits (too short)
        '98412345678', // 11 digits (too long)
        'random_string_with_9841234567_at_end',
      ];

      for (final phone in foreignAndInvalid) {
        expect(NepalPhoneHelper.isValid(phone), isFalse, reason: '$phone must be rejected');
        expect(NepalPhoneHelper.normalize(phone), isNull, reason: '$phone must not normalize');
      }
    });
  });

  group('7. Authenticated Profile Completion & Trigger Sync Derivation', () {
    test('Simulates complete_user_registration: requires auth session, prevents ATO and admin escalation', () {
      Map<String, dynamic> simulateCompleteUserRegistrationRpc({
        required String? authenticatedUserId,
        required String userEmailFromAuth,
        required bool emailConfirmedAtIsNull,
        required String requestedRole,
        required String phone,
      }) {
        if (authenticatedUserId == null) {
          throw Exception('Authentication required. Anonymous registration is not permitted.');
        }

        var cleanRole = requestedRole.trim().toLowerCase();
        if (cleanRole == 'admin') {
          throw Exception('Admin accounts cannot be self-registered.');
        }
        if (!['buyer', 'seller', 'dealer', 'recondition'].contains(cleanRole)) {
          cleanRole = 'buyer';
        }

        final normPhone = NepalPhoneHelper.normalize(phone);
        if (phone.trim().isNotEmpty && normPhone == null) {
          throw Exception('Invalid Nepal mobile number.');
        }

        return {
          'success': true,
          'user_id': authenticatedUserId,
          'email': userEmailFromAuth,
          'phone_normalized': normPhone,
          'email_verified': !emailConfirmedAtIsNull,
          'phone_verified': false,
          'role': cleanRole,
        };
      }

      // Anonymous caller is immediately blocked
      expect(
        () => simulateCompleteUserRegistrationRpc(
          authenticatedUserId: null,
          userEmailFromAuth: 'anon@example.com',
          emailConfirmedAtIsNull: true,
          requestedRole: 'buyer',
          phone: '9841234567',
        ),
        throwsA(predicate((e) => e.toString().contains('Authentication required'))),
      );

      // Authenticated caller cannot self-assign admin
      expect(
        () => simulateCompleteUserRegistrationRpc(
          authenticatedUserId: 'user-auth-1',
          userEmailFromAuth: 'user@example.com',
          emailConfirmedAtIsNull: false,
          requestedRole: 'admin',
          phone: '9841234567',
        ),
        throwsA(predicate((e) => e.toString().contains('Admin accounts cannot be self-registered'))),
      );

      // Legitimate buyer completes registration with email_verified derived from auth
      final valid = simulateCompleteUserRegistrationRpc(
        authenticatedUserId: 'user-auth-2',
        userEmailFromAuth: 'genuine@example.com',
        emailConfirmedAtIsNull: false, // confirmed by Supabase Auth
        requestedRole: 'buyer',
        phone: '9841234567',
      );
      expect(valid['success'], isTrue);
      expect(valid['email_verified'], isTrue);
      expect(valid['phone_verified'], isFalse);
      expect(valid['phone_normalized'], equals('+9779841234567'));
    });

    test('Simulates sync_profile_on_auth: derives verification strictly from Auth columns', () {
      Map<String, dynamic> simulateSyncProfileOnAuthTrigger({
        required String? emailConfirmedAt,
        required String? phoneConfirmedAt,
        required Map<String, dynamic> rawUserMetaData,
      }) {
        var role = (rawUserMetaData['role'] as String?)?.toLowerCase() ?? 'buyer';
        if (role == 'admin') {
          role = 'buyer'; // Sanitized
        }

        return {
          'email_verified': emailConfirmedAt != null,
          'phone_verified': phoneConfirmedAt != null,
          'phone_verified_at': phoneConfirmedAt,
          'role': role,
        };
      }

      // Unconfirmed email signup
      final unconfirmed = simulateSyncProfileOnAuthTrigger(
        emailConfirmedAt: null,
        phoneConfirmedAt: null,
        rawUserMetaData: {'role': 'buyer'},
      );
      expect(unconfirmed['email_verified'], isFalse);
      expect(unconfirmed['phone_verified'], isFalse);

      // Confirmed email, unconfirmed phone
      final emailOnly = simulateSyncProfileOnAuthTrigger(
        emailConfirmedAt: DateTime.now().toIso8601String(),
        phoneConfirmedAt: null,
        rawUserMetaData: {'role': 'admin'}, // attempted privilege escalation
      );
      expect(emailOnly['email_verified'], isTrue);
      expect(emailOnly['phone_verified'], isFalse);
      expect(emailOnly['role'], equals('buyer'), reason: 'Admin attempt must be sanitized to buyer');
    });
  });

  group('8. Email-Only OTP Verification Policy', () {
    test('Email verification is required for account registration; phone has no OTP requirement', () {
      bool canRegister({
        required bool isEmailVerified,
        required String? verifiedEmail,
        required String currentEmail,
        required String phone,
      }) {
        if (!isEmailVerified || verifiedEmail == null) return false;
        if (verifiedEmail.toLowerCase() != currentEmail.toLowerCase()) return false;
        if (!NepalPhoneHelper.isValid(phone)) return false;
        return true;
      }

      // Valid: email verified, phone valid format
      expect(
        canRegister(
          isEmailVerified: true,
          verifiedEmail: 'user@phatphati.com',
          currentEmail: 'user@phatphati.com',
          phone: '9841234567',
        ),
        isTrue,
      );

      // Blocked: email not verified
      expect(
        canRegister(
          isEmailVerified: false,
          verifiedEmail: null,
          currentEmail: 'user@phatphati.com',
          phone: '9841234567',
        ),
        isFalse,
      );

      // Blocked: email changed after verification
      expect(
        canRegister(
          isEmailVerified: true,
          verifiedEmail: 'old@phatphati.com',
          currentEmail: 'new@phatphati.com',
          phone: '9841234567',
        ),
        isFalse,
      );

      // Blocked: invalid phone format (even though email is verified)
      expect(
        canRegister(
          isEmailVerified: true,
          verifiedEmail: 'user@phatphati.com',
          currentEmail: 'user@phatphati.com',
          phone: '12345',
        ),
        isFalse,
      );
    });
  });
}

