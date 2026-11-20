import 'dart:convert';
import 'dart:typed_data';

import 'package:chdc_counselling/services/case_crypto_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CaseCryptoService service;
  late FlutterSecureStorage storage;
  late X25519 x25519;
  late AesGcm aes;
  late List<SimpleKeyPair> recipientKeys;
  late List<CommitteeRolePublicKey> publicKeys;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    storage = const FlutterSecureStorage();
    service = CaseCryptoService(secureStorage: storage);
    x25519 = X25519();
    aes = AesGcm.with256bits();
    recipientKeys = [
      await x25519.newKeyPair(),
      await x25519.newKeyPair(),
      await x25519.newKeyPair(),
    ];
    publicKeys = [];
    for (var i = 0; i < recipientKeys.length; i++) {
      final publicKey = await recipientKeys[i].extractPublicKey();
      publicKeys.add(CommitteeRolePublicKey(
        role: 'role_$i',
        publicKeyBase64: base64Encode(publicKey.bytes),
      ));
    }
  });

  tearDown(() {
    for (final key in recipientKeys) {
      key.destroy();
    }
  });

  test('encrypts each share for only its matching committee recipient',
      () async {
    final kMaster = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final bundle = await service.createBundle(
      caseId: 'case-encrypted-shares',
      kMaster: kMaster,
      committeePublicKeys: publicKeys,
    );

    expect(bundle.encryptedCommitteeShares, hasLength(3));
    for (var i = 0; i < bundle.encryptedCommitteeShares.length; i++) {
      final encrypted = bundle.encryptedCommitteeShares[i];
      final decrypted = await _decryptShare(
        encrypted: encrypted,
        recipientKey: recipientKeys[i],
        x25519: x25519,
        aes: aes,
      );
      expect(decrypted, isNotEmpty);

      for (var other = 0; other < recipientKeys.length; other++) {
        if (other == i) continue;
        expect(
          () => _decryptShare(
            encrypted: encrypted,
            recipientKey: recipientKeys[other],
            x25519: x25519,
            aes: aes,
          ),
          throwsA(anything),
        );
      }
    }
  });

  test('payload contains no raw shares, keys, or shard B', () async {
    final kMaster = Uint8List.fromList(List<int>.generate(32, (i) => 100 + i));
    final bundle = await service.createBundle(
      caseId: 'case-payload',
      kMaster: kMaster,
      committeePublicKeys: publicKeys,
    );
    final payload = service
        .buildSubmissionPayload(
          caseId: 'case-payload',
          caseName: 'Academic Stress',
          encryptedIdentity: const {
            'ciphertext': 'identity-ciphertext',
            'nonce': 'identity-nonce',
            'mac': 'identity-mac',
          },
          bundle: bundle,
        )
        .toJson();

    expect(payload.keys.toSet(), {
      'case_id',
      'case_name',
      'encrypted_identity',
      'wrapped_key_A',
      'wrapped_key_B',
      'shard_A',
      'committee_role_shares',
    });
    expect(payload.keys, isNot(contains('shard_B')));
    expect(payload.keys, isNot(contains('k_master')));
    expect(payload.keys, isNot(contains('k_student')));
    expect(payload.keys, isNot(contains('k_committee')));
    expect(payload.toString(), isNot(contains('quorumShares')));
    expect(payload.toString(), isNot(contains('case_shard_b_')));
    expect(
      await storage.read(key: 'case_shard_b_case-payload'),
      isNotNull,
    );
    expect(
      (payload['committee_role_shares'] as List<dynamic>),
      everyElement(isA<Map<String, String>>()),
    );
  });

  test('requires exactly three distinct committee roles', () async {
    final kMaster = Uint8List(32);
    expect(
      () => service.createBundle(
        caseId: 'case-invalid-keys',
        kMaster: kMaster,
        committeePublicKeys: publicKeys.sublist(0, 2),
      ),
      throwsArgumentError,
    );
  });

  test('student shards restore the AES-wrapped master key', () async {
    final kMaster = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final bundle = await service.createBundle(
      caseId: 'case-student-recovery',
      kMaster: kMaster,
      committeePublicKeys: publicKeys,
    );

    final recoveredBase64 = await service.unwrapWithStudentKey(
      caseId: 'case-student-recovery',
      shardA: bundle.shardA,
      wrappedKeyA: bundle.wrappedKeyA,
    );

    expect(base64Decode(recoveredBase64), kMaster);
  });

  test('two committee shares restore the AES-wrapped master key', () async {
    final kMaster = Uint8List.fromList(List<int>.generate(32, (i) => 50 + i));
    final bundle = await service.createBundle(
      caseId: 'case-committee-recovery',
      kMaster: kMaster,
      committeePublicKeys: publicKeys,
    );
    final decryptedShares = <String>[];
    for (var i = 0; i < 2; i++) {
      decryptedShares.add(await _decryptShare(
        encrypted: bundle.encryptedCommitteeShares[i],
        recipientKey: recipientKeys[i],
        x25519: x25519,
        aes: aes,
      ));
    }

    final recoveredBase64 = await service.unwrapWithCommitteeShares(
      shares: decryptedShares,
      wrappedKeyB: bundle.wrappedKeyB,
    );

    expect(base64Decode(recoveredBase64), kMaster);
  });

  test('prototype case UUID is RFC 4122 v4 shaped', () {
    final uuid = CaseCryptoService.generateCaseUuid();
    expect(
      uuid,
      matches(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
        r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
  });
}

Future<String> _decryptShare({
  required EncryptedCommitteeShare encrypted,
  required SimpleKeyPair recipientKey,
  required X25519 x25519,
  required AesGcm aes,
}) async {
  final ephemeral = SimplePublicKey(
    base64Decode(encrypted.ephemeralPublicKey),
    type: KeyPairType.x25519,
  );
  final sharedKey = await x25519.sharedSecretKey(
    keyPair: recipientKey,
    remotePublicKey: ephemeral,
  );
  final box = SecretBox.fromConcatenation(
    base64Decode(encrypted.ciphertext),
    nonceLength: 12,
    macLength: 16,
  );
  return utf8.decode(await aes.decrypt(box, secretKey: sharedKey));
}
