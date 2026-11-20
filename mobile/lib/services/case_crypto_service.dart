import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sss256/sss256.dart';

class CommitteeRolePublicKey {
  const CommitteeRolePublicKey({
    required this.role,
    required this.publicKeyBase64,
  });

  final String role;
  final String publicKeyBase64;

  SimplePublicKey toX25519PublicKey() {
    final bytes = base64Decode(publicKeyBase64);
    if (bytes.length != 32) {
      throw ArgumentError.value(
        bytes.length,
        'publicKeyBase64',
        'X25519 public keys must be 32 bytes',
      );
    }
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }
}

class EncryptedCommitteeShare {
  const EncryptedCommitteeShare({
    required this.role,
    required this.ciphertext,
    required this.ephemeralPublicKey,
  });

  final String role;
  final String ciphertext;
  final String ephemeralPublicKey;

  Map<String, String> toJson() => {
        'role': role,
        'ciphertext': ciphertext,
        'ephemeral_public_key': ephemeralPublicKey,
        'algorithm': 'x25519-aes-256-gcm',
      };
}

class CaseCryptoBundle {
  const CaseCryptoBundle({
    required this.wrappedKeyA,
    required this.shardA,
    required this.wrappedKeyB,
    required this.encryptedCommitteeShares,
  });

  final String wrappedKeyA;
  final String shardA;
  final String wrappedKeyB;
  final List<EncryptedCommitteeShare> encryptedCommitteeShares;
}

class CaseSubmissionPayload {
  const CaseSubmissionPayload(this._json);

  final Map<String, dynamic> _json;

  Map<String, dynamic> toJson() => Map.unmodifiable(_json);
}

class PrototypeCryptoSummary {
  const PrototypeCryptoSummary({
    required this.caseId,
    required this.caseName,
    required this.hasEncryptedIdentity,
    required this.hasWrappedKeyA,
    required this.hasShardA,
    required this.hasWrappedKeyB,
    required this.committeeShareCount,
    required this.shardBStored,
    required this.payloadStructure,
  });

  final String caseId;
  final String caseName;
  final bool hasEncryptedIdentity;
  final bool hasWrappedKeyA;
  final bool hasShardA;
  final bool hasWrappedKeyB;
  final int committeeShareCount;
  final bool shardBStored;
  final Map<String, dynamic> payloadStructure;

  Map<String, dynamic> toJson() => {
        'case_id': caseId,
        'case_name': caseName,
        'has_encrypted_identity': hasEncryptedIdentity,
        'has_wrapped_key_A': hasWrappedKeyA,
        'has_shard_A': hasShardA,
        'has_wrapped_key_B': hasWrappedKeyB,
        'committee_share_count': committeeShareCount,
        'shard_B_stored_in_secure_storage': shardBStored,
        'payload_structure': payloadStructure,
      };
}

class CaseCryptoService {
  CaseCryptoService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  final AesGcm _cipher = AesGcm.with256bits();
  final X25519 _keyExchange = X25519();

  static const AndroidOptions _androidOptions = AndroidOptions();
  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static String generateCaseUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final values = hex.toList(growable: false);
    return '${values.sublist(0, 4).join()}-${values.sublist(4, 6).join()}-'
        '${values.sublist(6, 8).join()}-${values.sublist(8, 10).join()}-'
        '${values.sublist(10, 16).join()}';
  }

  /// Generates disposable X25519 public keys for the local prototype only.
  ///
  /// Live deployments must replace this with authenticated role keys fetched
  /// from the future committee public-key endpoint.
  Future<List<CommitteeRolePublicKey>> generatePrototypeCommitteeKeys() async {
    const roles = <String>[
      'family',
      'counsellor',
      'committee',
    ];
    final result = <CommitteeRolePublicKey>[];
    for (final role in roles) {
      final keyPair = await _keyExchange.newKeyPair();
      try {
        final publicKey = await keyPair.extractPublicKey();
        result.add(CommitteeRolePublicKey(
          role: role,
          publicKeyBase64: base64Encode(publicKey.bytes),
        ));
      } finally {
        keyPair.destroy();
      }
    }
    return List.unmodifiable(result);
  }

  Future<bool> isShardBStored(String caseId) async {
    final value = await _secureStorage.read(
      key: 'case_shard_b_$caseId',
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    return value != null;
  }

  /// Creates the key bundle and encrypts each committee share for its role.
  ///
  /// The backend contract does not currently define committee-key discovery or
  /// case submission. Callers must obtain these authenticated X25519 keys from
  /// the eventual key endpoint and pass exactly three distinct roles.
  Future<CaseCryptoBundle> createBundle({
    required String caseId,
    required Uint8List kMaster,
    required List<CommitteeRolePublicKey> committeePublicKeys,
  }) async {
    if (kMaster.length != 32) {
      throw ArgumentError.value(kMaster.length, 'kMaster', 'Must be 32 bytes');
    }
    _validateCommitteeKeys(committeePublicKeys);

    final studentKey = await _randomKeyBytes();
    final kCommittee = await _randomKeyBytes();
    final shardB = await _randomKeyBytes();
    Uint8List? studentShardA;
    List<String>? rawShares;
    Uint8List? committeeBytes;

    try {
      final wrappedKeyA =
          await _wrapKey(kMaster: kMaster, wrappingKey: studentKey);
      final wrappedKeyB =
          await _wrapKey(kMaster: kMaster, wrappingKey: kCommittee);

      studentShardA = Uint8List.fromList(List<int>.generate(
        32,
        (i) => studentKey[i] ^ shardB[i],
      ));

      await _secureStorage.write(
        key: 'case_shard_b_$caseId',
        value: base64Encode(shardB),
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

      committeeBytes = Uint8List.fromList(kCommittee);
      rawShares = splitSecret(
        secret: base64Encode(committeeBytes),
        treshold: 2,
        shares: 3,
      );
      final encryptedShares = <EncryptedCommitteeShare>[];
      for (var i = 0; i < rawShares.length; i++) {
        final shareBytes = Uint8List.fromList(utf8.encode(rawShares[i]));
        try {
          encryptedShares.add(await _encryptShare(
            roleKey: committeePublicKeys[i],
            shareBytes: shareBytes,
          ));
        } finally {
          shareBytes.fillRange(0, shareBytes.length, 0);
          rawShares[i] = '';
        }
      }

      return CaseCryptoBundle(
        wrappedKeyA: wrappedKeyA,
        shardA: base64Encode(studentShardA),
        wrappedKeyB: wrappedKeyB,
        encryptedCommitteeShares: List.unmodifiable(encryptedShares),
      );
    } finally {
      studentKey.fillRange(0, studentKey.length, 0);
      kCommittee.fillRange(0, kCommittee.length, 0);
      shardB.fillRange(0, shardB.length, 0);
      if (committeeBytes != null) {
        committeeBytes.fillRange(0, committeeBytes.length, 0);
      }
      if (studentShardA != null) {
        studentShardA.fillRange(0, studentShardA.length, 0);
      }
      if (rawShares != null) {
        for (var i = 0; i < rawShares.length; i++) {
          rawShares[i] = '';
        }
        rawShares.clear();
      }
    }
  }

  /// Builds only the fields permitted in the Step 7 case submission.
  CaseSubmissionPayload buildSubmissionPayload({
    required String caseId,
    required String caseName,
    required Map<String, dynamic> encryptedIdentity,
    required CaseCryptoBundle bundle,
  }) {
    if (bundle.encryptedCommitteeShares.length != 3) {
      throw StateError('Exactly three encrypted committee shares are required');
    }
    return CaseSubmissionPayload({
      'case_id': caseId,
      'case_name': caseName,
      'encrypted_identity':
          Map<String, dynamic>.unmodifiable(encryptedIdentity),
      'wrapped_key_A': bundle.wrappedKeyA,
      'wrapped_key_B': bundle.wrappedKeyB,
      'shard_A': bundle.shardA,
      'committee_role_shares': bundle.encryptedCommitteeShares
          .map((share) => share.toJson())
          .toList(),
    });
  }

  Future<EncryptedCommitteeShare> _encryptShare({
    required CommitteeRolePublicKey roleKey,
    required Uint8List shareBytes,
  }) async {
    final ephemeralKeyPair = await _keyExchange.newKeyPair();
    try {
      final sharedKey = await _keyExchange.sharedSecretKey(
        keyPair: ephemeralKeyPair,
        remotePublicKey: roleKey.toX25519PublicKey(),
      );
      final secretBox = await _cipher.encrypt(
        shareBytes,
        secretKey: sharedKey,
      );
      final ephemeralPublicKey =
          (await ephemeralKeyPair.extractPublicKey()).bytes;
      return EncryptedCommitteeShare(
        role: roleKey.role,
        ciphertext: base64Encode(secretBox.concatenation()),
        ephemeralPublicKey: base64Encode(ephemeralPublicKey),
      );
    } finally {
      ephemeralKeyPair.destroy();
    }
  }

  void _validateCommitteeKeys(List<CommitteeRolePublicKey> keys) {
    if (keys.length != 3) {
      throw ArgumentError.value(
        keys.length,
        'committeePublicKeys',
        'Exactly three committee role public keys are required',
      );
    }
    final roles = keys.map((key) => key.role).toSet();
    if (roles.length != 3 || keys.any((key) => key.role.trim().isEmpty)) {
      throw ArgumentError.value(
        keys,
        'committeePublicKeys',
        'Committee roles must be three distinct non-empty values',
      );
    }
  }

  Future<Uint8List> _randomKeyBytes() async {
    final key = await _cipher.newSecretKey();
    return Uint8List.fromList(await key.extractBytes());
  }

  Future<String> _wrapKey({
    required Uint8List kMaster,
    required Uint8List wrappingKey,
  }) async {
    final secretBox = await _cipher.encrypt(
      kMaster,
      secretKey: SecretKey(wrappingKey),
    );
    return base64Encode(secretBox.concatenation());
  }

  Future<String> unwrapWithStudentKey({
    required String caseId,
    required String shardA,
    required String wrappedKeyA,
  }) async {
    final shardABytes = base64Decode(shardA);
    final shardBBase64 = await _secureStorage.read(
      key: 'case_shard_b_$caseId',
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    if (shardBBase64 == null) {
      throw StateError('Student shard B not found for case $caseId');
    }

    final shardB = base64Decode(shardBBase64);
    try {
      final kStudent = Uint8List.fromList(List<int>.generate(
        32,
        (i) => shardABytes[i] ^ shardB[i],
      ));
      try {
        final master = await _unwrapKey(
          wrappedKeyBase64: wrappedKeyA,
          wrappingKey: kStudent,
        );
        return base64Encode(master);
      } finally {
        kStudent.fillRange(0, kStudent.length, 0);
      }
    } finally {
      shardB.fillRange(0, shardB.length, 0);
      shardABytes.fillRange(0, shardABytes.length, 0);
    }
  }

  Future<String> unwrapWithCommitteeShares({
    required List<String> shares,
    required String wrappedKeyB,
  }) async {
    if (shares.length < 2) {
      throw ArgumentError.value(shares.length, 'shares', 'Two shares required');
    }

    final committeeBase64 = restoreSecret(shares: shares, isBase64: true);
    final kCommittee = base64Decode(committeeBase64);
    try {
      final master = await _unwrapKey(
        wrappedKeyBase64: wrappedKeyB,
        wrappingKey: kCommittee,
      );
      return base64Encode(master);
    } finally {
      kCommittee.fillRange(0, kCommittee.length, 0);
    }
  }

  Future<Uint8List> _unwrapKey({
    required String wrappedKeyBase64,
    required Uint8List wrappingKey,
  }) async {
    final secretBox = SecretBox.fromConcatenation(
      base64Decode(wrappedKeyBase64),
      nonceLength: 12,
      macLength: 16,
    );
    return Uint8List.fromList(await _cipher.decrypt(
      secretBox,
      secretKey: SecretKey(wrappingKey),
    ));
  }

  void zeroBuffer(Uint8List buffer) {
    buffer.fillRange(0, buffer.length, 0);
  }
}
