import 'package:flutter/foundation.dart';

import '../../core/secuirity/identity_crypto_service.dart';
import '../../core/secuirity/pii_scrubber_service.dart';
import 'models/case_model.dart';
import 'utils/pseudonym_generator.dart';

class CaseController extends ChangeNotifier {
  final List<CaseModel> _cases = [];
  final PiiScrubberService _piiScrubber = PiiScrubberService();
  final IdentityCryptoService _identityCrypto = IdentityCryptoService();

  List<CaseModel> get cases => List.unmodifiable(_cases);

  /// Submits a new anonymized case request with on-device PII scrubbing
  /// and AES-256-GCM encryption of the student's phone number.
  Future<void> createCase({
    required String phoneNumber,
    required String category,
    required String description,
  }) async {
    // 1. Scrub incidental PII from the crisis narrative locally (Section 3.1)
    final scrubbedDescription = await _piiScrubber.scrubNarrative(description);

    // 2. Generate K_master and encrypt the student's phone number via AES-256-GCM (Section 4.1)
    final encryptedIdentity =
        await _identityCrypto.encryptPhoneNumber(phoneNumber);

    // Note: In the next milestone, encryptedIdentity.kMasterBytes will be wrapped
    // by K_family and K_committee before zeroing the buffer.
    _identityCrypto.zeroKeyBuffer(encryptedIdentity.kMasterBytes);

    final newCase = CaseModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      pseudonym: PseudonymGenerator.generate(),
      category: category,
      description: scrubbedDescription,
      encryptedPhoneCiphertext: encryptedIdentity.cipherTextBase64,
      encryptionNonce: encryptedIdentity.nonceBase64,
      encryptionMac: encryptedIdentity.macBase64,
      status: CaseStatus.open,
      createdAt: DateTime.now(),
    );

    _cases.insert(0, newCase);
    notifyListeners();
  }

  @override
  void dispose() {
    _piiScrubber.dispose();
    super.dispose();
  }
}