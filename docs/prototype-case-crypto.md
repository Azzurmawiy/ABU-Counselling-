# Prototype Case Cryptography and Release APK

Date: 20 November 2026

This document records the prototype case-creation cryptography, verification,
release build, and website download implementation added to the repository.
It is intended for developers and reviewers. It is not a production threat
model or a production counselling-system security approval.

## Implemented flow

Case creation starts in
`mobile/lib/features/cases/screens/create_case_screen.dart`. The submit handler
validates the phone number, matric number, category, and description, then
calls `CaseController.createCase()` from
`mobile/lib/features/cases/case_controller.dart`.

The prototype flow is:

1. Scrub the crisis narrative with `PiiScrubberService`.
2. Generate a 256-bit `k_master`.
3. Encrypt the phone number and matric number as a JSON identity payload using
   AES-256-GCM.
4. Generate a 256-bit `k_student`.
5. Generate a 256-bit `k_committee`.
6. Wrap `k_master` with `k_student` and `k_committee` using AES-256-GCM.
7. XOR-split `k_student` into `shard_A` and `shard_B`.
8. Persist `shard_B` in `FlutterSecureStorage` for the case UUID.
9. Split `k_committee` into three Shamir shares with a threshold of two.
10. Encrypt each committee share for the matching family, counsellor, or
    committee X25519 public key.
11. Return a local summary and the in-memory case model without performing a
    live case submission.

The live backend still has no case submission or committee-key endpoint.
Prototype submission therefore remains local-only.

## Key classes

### `IdentityCryptoService`

`mobile/lib/core/secuirity/identity_crypto_service.dart`:

- Creates `k_master`.
- Uses a fresh 12-byte nonce for AES-256-GCM identity encryption.
- Includes `phone_number` and `matric_number` in the encrypted plaintext.
- Returns the raw master key only long enough to create wrapped keys.
- Zeros the returned master-key buffer after the bundle is created.

The `matricNumber` is normalized to uppercase before encryption.

### `CaseCryptoService`

`mobile/lib/services/case_crypto_service.dart`:

- Generates a UUIDv4-shaped case ID.
- Wraps `k_master` as `wrapped_key_A` and `wrapped_key_B`.
- XOR-splits `k_student`.
- Writes `shard_B` under
  `case_shard_b_<case_uuid>` in `FlutterSecureStorage`.
- Splits `k_committee` with 2-of-3 Shamir sharing.
- Encrypts each share with X25519 and AES-256-GCM.
- Builds the submission-shaped payload.
- Provides student and committee recovery methods for tests.

The recovery methods recombine or unwrap the relevant keys only in memory and
are not exposed as student-facing decryption controls in the case UI.

## Committee public keys

The prototype currently calls:

```dart
final committeeKeys =
    await caseCrypto.generatePrototypeCommitteeKeys();
```

This creates disposable X25519 key pairs for:

- `family`
- `counsellor`
- `committee`

It returns only the public keys. The private keys are destroyed immediately
after public-key extraction and cannot be retrieved later. This is sufficient
for generating and inspecting an encrypted prototype bundle, but it is not
sufficient for real quorum recovery.

For a live implementation:

1. Generate and securely retain each role's private X25519 key outside the
   student app.
2. Add an authenticated committee-key discovery endpoint.
3. Return only public keys to the student app.
4. Route private-key-controlled share encryption/decryption through authorized
   quorum services.
5. Replace locally generated keys with endpoint-provided public keys.
6. Replace client-generated IDs with IDs assigned by the live case endpoint.

No committee private key was or should be embedded in the APK.

## Frozen payload contract

The submission payload uses `snake_case` field names and contains exactly these
top-level fields:

```text
case_id
case_name
encrypted_identity
wrapped_key_A
wrapped_key_B
shard_A
committee_role_shares
```

`encrypted_identity` contains `ciphertext`, `nonce`, and `mac`.

Each `committee_role_shares` entry contains:

```text
role
ciphertext
ephemeral_public_key
algorithm
```

The payload never includes `k_master`, `k_student`, `k_committee`, raw
committee shares, or `shard_B`.

The payload test asserts the exact top-level key set and also verifies that
two matching committee shares can recover `k_committee` and that student
shards can recover `k_student`.

## Student submit behavior

`CreateCaseScreen._submit()` calls `CaseController.createCase()` and receives a
`PrototypeCryptoSummary`. The summary reports:

- Case UUID and case name.
- Encrypted identity presence.
- Wrapped A/B key presence.
- Shard A presence.
- Committee share count.
- Whether Shard B was found in secure storage.
- The snake-case payload structure.

The app displays this as a local prototype summary, explicitly states that no
live case endpoint was called, and returns to the prior screen.

No raw key or ciphertext values are displayed.

## Automated verification

Commands run in the `mobile` directory:

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
```

Verification result:

- `flutter analyze`: no issues.
- `flutter test`: 40 tests passed.
- Debug APK build: successful.
- Release APK build: successful.
- Release APK signature: Android APK Signature Scheme v2 verified.
- Web build: successful.
- Web tests: 33 passed.

The cryptographic tests cover:

- Identity encryption and matric-number JSON plaintext.
- PII scrubbing.
- Exact payload key allowlist.
- Rejection of extra committee roles or duplicate roles.
- Matching-recipient share decryption.
- Student shard recovery.
- Two-share committee quorum recovery.
- UUIDv4 shape.

The Django download-route test requires the configured PostgreSQL environment.
The endpoint was also smoke-tested through Django test request handling and
returned `200` with an APK attachment.

## Release APK and website download

The signed release APK was written to:

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

For the website download route, the same file was placed at:

```text
backend/media/app-release.apk
```

Django serves it through `GET /download-app/` using the
`apps.common.views.download_app` view. The web confirmation page links to
`VITE_APP_DOWNLOAD_URL`, with `/download-app/` as a fallback.

The built artifact was approximately 61 MB. Its SHA-256 at build time was:

```text
4d52d95d0248760f4aae7595bedf337d3e5235fb6f5df68d935b7fca14199bc3
```

The APK was compiled with:

```text
USE_MOCK=false
API_BASE_URL=http://207.180.195.101/api/v1/
WEB_REGISTRATION_URL=http://207.180.195.101/register
```

For production, HTTPS URLs and an infrastructure-managed signing key should
replace these demonstration values.

## Prototype-only placeholders

Before production use, replace or complete:

- Local X25519 committee key generation.
- Client-generated case UUID ownership.
- In-memory case storage.
- Local-only prototype submission with no HTTP case POST.
- Demo API and web URLs.
- Temporary or unregistered signing-key infrastructure.
- The prototype biometric gate.
- The missing backend case model, persistence, authorization, and audit trail.

## Security notes

- Do not enter real sensitive counselling details until the live backend case
  and authorization design is implemented and reviewed.
- Never commit signing keystores, signing passwords, private keys, OTPs, or
  production environment files.
- Store committee private keys in a controlled server or hardware-backed
  service, never in the APK or a student-facing repository.
- Preserve and back up a production signing key; keystore loss prevents signed
  updates to the existing Android package.
