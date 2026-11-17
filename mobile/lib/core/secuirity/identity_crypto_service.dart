import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class EncryptedIdentityPayload {
  /// Raw 32-byte K_master held briefly in memory until wrapped by K_family & K_committee.
  final Uint8List kMasterBytes;
  final String cipherTextBase64;
  final String nonceBase64;
  final String macBase64;

  EncryptedIdentityPayload({
    required this.kMasterBytes,
    required this.cipherTextBase64,
    required this.nonceBase64,
    required this.macBase64,
  });
}

class IdentityCryptoService {
  // AES-256-GCM (256-bit key, 96-bit nonce, 128-bit GCM authentication tag)
  final AesGcm _cipher = AesGcm.with256bits();

  /// Generates a fresh 256-bit K_master and encrypts the student's phone number
  /// via AES-256-GCM (Section 4.1 Step 1).
  Future<EncryptedIdentityPayload> encryptPhoneNumber(String phoneNumber) async {
    // 1. Generate a fresh 32-byte K_master
    final secretKey = await _cipher.newSecretKey();
    final rawKeyBytes = Uint8List.fromList(await secretKey.extractBytes());

    // 2. Generate a random 12-byte (96-bit) nonce
    final nonce = _cipher.newNonce();

    // 3. Encrypt the UTF-8 encoded phone number
    final plaintextBytes = utf8.encode(phoneNumber.trim());
    final secretBox = await _cipher.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return EncryptedIdentityPayload(
      kMasterBytes: rawKeyBytes,
      cipherTextBase64: base64Encode(secretBox.cipherText),
      nonceBase64: base64Encode(secretBox.nonce),
      macBase64: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Best-effort zeroing of the K_master buffer after wrapping.
  void zeroKeyBuffer(Uint8List buffer) {
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = 0;
    }
  }
}
