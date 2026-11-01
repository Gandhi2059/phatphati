import 'package:flutter_test/flutter_test.dart';
import 'package:bid_app/utils/nepal_phone_helper.dart';

void main() {
  group('NepalPhoneHelper Validation & Normalization Tests', () {
    test('Validates 10-digit Nepal mobile numbers (NTC 984, 985, 986)', () {
      expect(NepalPhoneHelper.isValid('9841234567'), isTrue);
      expect(NepalPhoneHelper.normalize('9841234567'), equals('+9779841234567'));
      expect(NepalPhoneHelper.isValid('9851098765'), isTrue);
      expect(NepalPhoneHelper.isValid('9860123456'), isTrue);
    });

    test('Validates 10-digit Nepal mobile numbers (Ncell 980, 981, 982)', () {
      expect(NepalPhoneHelper.isValid('9801234567'), isTrue);
      expect(NepalPhoneHelper.normalize('9801234567'), equals('+9779801234567'));
      expect(NepalPhoneHelper.isValid('9812345678'), isTrue);
      expect(NepalPhoneHelper.isValid('9823456789'), isTrue);
    });

    test('Validates 10-digit Nepal mobile numbers (97x & 96x Series)', () {
      expect(NepalPhoneHelper.isValid('9741234567'), isTrue);
      expect(NepalPhoneHelper.normalize('9741234567'), equals('+9779741234567'));
      expect(NepalPhoneHelper.isValid('9761234567'), isTrue);
      expect(NepalPhoneHelper.isValid('9611234567'), isTrue);
    });

    test('Handles international prefix variations (+977, 977, spaces, dashes)', () {
      expect(NepalPhoneHelper.isValid('+9779841234567'), isTrue);
      expect(NepalPhoneHelper.normalize('+9779841234567'), equals('+9779841234567'));

      expect(NepalPhoneHelper.isValid('+977 9841234567'), isTrue);
      expect(NepalPhoneHelper.normalize('+977 9841234567'), equals('+9779841234567'));

      expect(NepalPhoneHelper.isValid('977-9841234567'), isTrue);
      expect(NepalPhoneHelper.normalize('977-9841234567'), equals('+9779841234567'));

      expect(NepalPhoneHelper.isValid('00977 984-123-4567'), isTrue);
      expect(NepalPhoneHelper.normalize('00977 984-123-4567'), equals('+9779841234567'));
    });

    test('Rejects invalid phone numbers', () {
      // Too short
      expect(NepalPhoneHelper.isValid('984123456'), isFalse);
      expect(NepalPhoneHelper.normalize('984123456'), isNull);

      // Too long
      expect(NepalPhoneHelper.isValid('98412345678'), isFalse);
      expect(NepalPhoneHelper.normalize('98412345678'), isNull);

      // Invalid starting digits for mobile (e.g. landline starting with 01, or 91x)
      expect(NepalPhoneHelper.isValid('014234567'), isFalse);
      expect(NepalPhoneHelper.isValid('9141234567'), isFalse);
      expect(NepalPhoneHelper.isValid('8841234567'), isFalse);

      // Letters and special characters
      expect(NepalPhoneHelper.isValid('98412abcde'), isFalse);
      expect(NepalPhoneHelper.isValid(''), isFalse);
      expect(NepalPhoneHelper.isValid(null), isFalse);
    });

    test('Display formatting and masking', () {
      expect(NepalPhoneHelper.formatDisplay('9841234567'), equals('+977 984-1234567'));
      expect(NepalPhoneHelper.maskPhone('9841234567'), equals('+977 984***4567'));
    });

    test('Detects phone number equality and changes', () {
      expect(NepalPhoneHelper.areSame('9841234567', '+9779841234567'), isTrue);
      expect(NepalPhoneHelper.areSame('+977 984-1234567', '9841234567'), isTrue);
      expect(NepalPhoneHelper.areSame('9841234567', '9851234567'), isFalse);
      expect(NepalPhoneHelper.areSame('9841234567', 'invalid'), isFalse);
    });
  });
}
