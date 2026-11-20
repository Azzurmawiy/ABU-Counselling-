import 'package:flutter/foundation.dart';

import '../../core/secuirity/identity_crypto_service.dart';
import '../../core/secuirity/pii_scrubber_service.dart';
import '../../services/case_crypto_service.dart';
import 'models/case_model.dart';
import 'utils/pseudonym_generator.dart';

class CaseController extends ChangeNotifier {
  final List<CaseModel> _cases = [];
  final PiiScrubberService _piiScrubber = PiiScrubberService();
  final IdentityCryptoService _identityCrypto = IdentityCryptoService();
  final CaseCryptoService _caseCrypto = CaseCryptoService();

  List<CaseModel> get cases => List.unmodifiable(_cases);

  /// Submits a new anonymized case request with on-device PII scrubbing
  /// and AES-256-GCM encryption of the student's phone number.
  Future<PrototypeCryptoSummary?> createCase({
    required String phoneNumber,
    required String category,
    required String description,
    String? matricNumber,
    List<CommitteeRolePublicKey>? committeePublicKeys,
  }) async {
    // Prototype-only UUID until the live case endpoint provides/owns IDs.
    final caseId = CaseCryptoService.generateCaseUuid();

    // 1. Scrub incidental PII from the crisis narrative locally (Section 3.1)
    final scrubbedDescription = await _piiScrubber.scrubNarrative(description);

    // 2. Generate K_master and encrypt the student's phone number via AES-256-GCM (Section 4.1)
    final encryptedIdentity = await _identityCrypto.encryptIdentity(
      phoneNumber: phoneNumber,
      matricNumber: matricNumber,
    );
    PrototypeCryptoSummary? summary;
    CaseCryptoBundle? cryptoBundle;
    try {
      // TODO: Live build: fetch authenticated keys from the committee-key endpoint.
      // This disposable local-only path is intentionally separate from live submission.
      final prototypeKeys = committeePublicKeys ??
          await _caseCrypto.generatePrototypeCommitteeKeys();
      cryptoBundle = await _caseCrypto.createBundle(
        caseId: caseId,
        kMaster: encryptedIdentity.kMasterBytes,
        committeePublicKeys: prototypeKeys,
      );
      final payload = _caseCrypto.buildSubmissionPayload(
        caseId: caseId,
        caseName: category,
        encryptedIdentity: {
          'ciphertext': encryptedIdentity.cipherTextBase64,
          'nonce': encryptedIdentity.nonceBase64,
          'mac': encryptedIdentity.macBase64,
        },
        bundle: cryptoBundle,
      );
      final shardBStored = await _caseCrypto.isShardBStored(caseId);
      final payloadJson = payload.toJson();
      final payloadStructure = <String, dynamic>{
        'top_level_keys': payloadJson.keys.toList(growable: false),
        'encrypted_identity_keys':
            (payloadJson['encrypted_identity'] as Map<String, dynamic>)
                .keys
                .toList(growable: false),
        'committee_share_keys':
            (payloadJson['committee_role_shares'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map((share) => share.keys.toList(growable: false))
                .toList(growable: false),
      };
      summary = PrototypeCryptoSummary(
        caseId: caseId,
        caseName: category,
        hasEncryptedIdentity: payloadJson['encrypted_identity'] != null,
        hasWrappedKeyA: cryptoBundle.wrappedKeyA.isNotEmpty,
        hasShardA: cryptoBundle.shardA.isNotEmpty,
        hasWrappedKeyB: cryptoBundle.wrappedKeyB.isNotEmpty,
        committeeShareCount: cryptoBundle.encryptedCommitteeShares.length,
        shardBStored: shardBStored,
        payloadStructure: payloadStructure,
      );
      debugPrint(
        'PROTOTYPE CASE CRYPTO SUMMARY: '
        '${summary.toJson()} '
        '(raw keys and ciphertext values omitted)',
      );
    } finally {
      _identityCrypto.zeroKeyBuffer(encryptedIdentity.kMasterBytes);
    }

    final newCase = CaseModel(
      id: caseId,
      pseudonym: PseudonymGenerator.generate(),
      category: category,
      description: scrubbedDescription,
      encryptedPhoneCiphertext: encryptedIdentity.cipherTextBase64,
      encryptionNonce: encryptedIdentity.nonceBase64,
      encryptionMac: encryptedIdentity.macBase64,
      wrappedKeyA: cryptoBundle.wrappedKeyA,
      shardA: cryptoBundle.shardA,
      wrappedKeyB: cryptoBundle.wrappedKeyB,
      encryptedCommitteeShares: cryptoBundle.encryptedCommitteeShares,
      status: CaseStatus.open,
      createdAt: DateTime.now(),
    );

    _cases.insert(0, newCase);
    notifyListeners();
    return summary;
  }

  /// Prepares the Step 7 payload for the eventual backend case endpoint.
  ///
  /// The repository has no case endpoint or committee-key endpoint yet, so
  /// authenticated X25519 role keys must be supplied by the caller.
  Future<CaseSubmissionPayload> createCaseSubmission({
    required String caseId,
    required String caseName,
    required String phoneNumber,
    required String matricNumber,
    required List<CommitteeRolePublicKey> committeePublicKeys,
  }) async {
    final encryptedIdentity = await _identityCrypto.encryptIdentity(
      phoneNumber: phoneNumber,
      matricNumber: matricNumber,
    );
    try {
      final bundle = await _caseCrypto.createBundle(
        caseId: caseId,
        kMaster: encryptedIdentity.kMasterBytes,
        committeePublicKeys: committeePublicKeys,
      );
      final payload = _caseCrypto.buildSubmissionPayload(
        caseId: caseId,
        caseName: caseName,
        encryptedIdentity: {
          'ciphertext': encryptedIdentity.cipherTextBase64,
          'nonce': encryptedIdentity.nonceBase64,
          'mac': encryptedIdentity.macBase64,
        },
        bundle: bundle,
      );
      return CaseSubmissionPayload({
        ...payload.toJson(),
      });
    } finally {
      _identityCrypto.zeroKeyBuffer(encryptedIdentity.kMasterBytes);
    }
  }

  @override
  void dispose() {
    _piiScrubber.dispose();
    super.dispose();
  }
}
