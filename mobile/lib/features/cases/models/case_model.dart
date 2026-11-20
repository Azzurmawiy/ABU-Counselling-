import '../../../services/case_crypto_service.dart';

enum CaseStatus { open, inProgress, closed }

class CaseModel {
  final String id;
  final String pseudonym; // Anonymized student identifier (e.g., "Pink Flame")
  final String category; // e.g., "Academic Stress", "Personal Guidance"
  final String description; // PII-scrubbed narrative
  final String?
      encryptedPhoneCiphertext; // AES-256-GCM encrypted phone number (Base64)
  final String? encryptionNonce; // 96-bit GCM nonce (Base64)
  final String? encryptionMac; // 128-bit GCM auth tag (Base64)
  final String? wrappedKeyA;
  final String? shardA;
  final String? wrappedKeyB;
  final List<EncryptedCommitteeShare> encryptedCommitteeShares;
  final CaseStatus status;
  final DateTime createdAt;

  const CaseModel({
    required this.id,
    required this.pseudonym,
    required this.category,
    required this.description,
    this.encryptedPhoneCiphertext,
    this.encryptionNonce,
    this.encryptionMac,
    this.wrappedKeyA,
    this.shardA,
    this.wrappedKeyB,
    this.encryptedCommitteeShares = const [],
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pseudonym': pseudonym,
        'category': category,
        'description': description,
        if (encryptedPhoneCiphertext != null)
          'encryptedPhoneCiphertext': encryptedPhoneCiphertext,
        if (encryptionNonce != null) 'encryptionNonce': encryptionNonce,
        if (encryptionMac != null) 'encryptionMac': encryptionMac,
        if (wrappedKeyA != null) 'wrappedKeyA': wrappedKeyA,
        if (shardA != null) 'shardA': shardA,
        if (wrappedKeyB != null) 'wrappedKeyB': wrappedKeyB,
        'committee_role_shares':
            encryptedCommitteeShares.map((share) => share.toJson()).toList(),
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CaseModel.fromJson(Map<String, dynamic> json) => CaseModel(
        id: json['id'] as String,
        pseudonym: json['pseudonym'] as String,
        category: json['category'] as String,
        description: json['description'] as String,
        encryptedPhoneCiphertext: json['encryptedPhoneCiphertext'] as String?,
        encryptionNonce: json['encryptionNonce'] as String?,
        encryptionMac: json['encryptionMac'] as String?,
        wrappedKeyA: json['wrappedKeyA'] as String?,
        shardA: json['shardA'] as String?,
        wrappedKeyB: json['wrappedKeyB'] as String?,
        encryptedCommitteeShares:
            (json['committee_role_shares'] as List<dynamic>?)
                    ?.map((share) => EncryptedCommitteeShare(
                          role: share['role'] as String,
                          ciphertext: share['ciphertext'] as String,
                          ephemeralPublicKey:
                              share['ephemeral_public_key'] as String,
                        ))
                    .toList() ??
                const [],
        status: CaseStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
