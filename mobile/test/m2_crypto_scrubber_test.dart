import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chdc_counselling/core/secuirity/identity_crypto_service.dart';
import 'package:chdc_counselling/core/secuirity/pii_scrubber_service.dart';

void main() {
  group('M2 On-Device PII Scrubbing & AES-256-GCM Encryption', () {
    test(
        'Encrypts phone number with AES-256-GCM and decrypts cleanly with K_master',
        () async {
      final cryptoService = IdentityCryptoService();
      const studentPhone = '+2348012345678';

      // Encrypt
      final payload = await cryptoService.encryptPhoneNumber(studentPhone);

      expect(payload.kMasterBytes.length, 32); // 256-bit key
      expect(payload.cipherTextBase64, isNotEmpty);
      expect(payload.nonceBase64, isNotEmpty);
      expect(payload.macBase64, isNotEmpty);

      // Verify round-trip decryption using K_master
      final cipher = AesGcm.with256bits();
      final secretKey = SecretKey(payload.kMasterBytes);
      final secretBox = SecretBox(
        base64Decode(payload.cipherTextBase64),
        nonce: base64Decode(payload.nonceBase64),
        mac: Mac(base64Decode(payload.macBase64)),
      );

      final decryptedBytes = await cipher.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      expect(utf8.decode(decryptedBytes), studentPhone);

      // Verify memory buffer zeroing
      cryptoService.zeroKeyBuffer(payload.kMasterBytes);
      expect(payload.kMasterBytes.every((b) => b == 0), isTrue);
    });

    test('encrypts phone number and matric number in the identity payload',
        () async {
      final cryptoService = IdentityCryptoService();
      final payload = await cryptoService.encryptIdentity(
        phoneNumber: '08031234567',
        matricNumber: 'u25co0001',
      );
      final secretBox = SecretBox(
        base64Decode(payload.cipherTextBase64),
        nonce: base64Decode(payload.nonceBase64),
        mac: Mac(base64Decode(payload.macBase64)),
      );
      final plaintext = await AesGcm.with256bits().decrypt(
        secretBox,
        secretKey: SecretKey(payload.kMasterBytes),
      );

      expect(jsonDecode(utf8.decode(plaintext)), {
        'phone_number': '08031234567',
        'matric_number': 'U25CO0001',
      });
      cryptoService.zeroKeyBuffer(payload.kMasterBytes);
    });

    test(
        'Regex layer scrubs Nigerian phone, email, reg number, and room location',
        () {
      final scrubber = PiiScrubberService();
      const rawNarrative =
          'My name is U19CO1024 in Room 204B, call 08012345678 or email student@abu.edu.ng.';

      final scrubbed = scrubber.scrubRegexPatterns(rawNarrative);
      expect(scrubbed, contains('[ID]'));
      expect(scrubbed, contains('[LOCATION]'));
      expect(scrubbed, contains('[PHONE]'));
      expect(scrubbed, contains('[EMAIL]'));
    });
  });
}
