import 'package:flutter/services.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

class PiiScrubberService {
  final _entityExtractor = EntityExtractor(
    language: EntityExtractorLanguage.english,
  );

  /// Downloads the offline ML Kit entity extraction model if not already cached.
  Future<void> initialize() async {
    final modelManager = EntityExtractorModelManager();
    final isDownloaded = await modelManager.isModelDownloaded(
      EntityExtractorLanguage.english.name,
    );
    if (!isDownloaded) {
      await modelManager.downloadModel(
        EntityExtractorLanguage.english.name,
        isWifiRequired: false,
      );
    }
  }

  /// Synchronous regex pass for structured local/campus identifiers.
  String scrubRegexPatterns(String rawText) {
    String scrubbed = rawText;

    final patterns = <RegExp, String>{
      // Email addresses
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'): '[EMAIL]',
      // Nigerian & international phone numbers (+234..., 080..., 070..., 090..., 081...)
      RegExp(r'(\+?234|0)[789][01]\d{8}\b'): '[PHONE]',
      // ABU matriculation / registration numbers (e.g., U19CO1024, P21EG8012)
      RegExp(r'\b[A-Z]\d{2}[A-Z]{2,4}\d{4}\b', caseSensitive: false): '[ID]',
      // Campus rooms, blocks, hostels, or halls (e.g., "Room 204B", "Block A", "Suleiman Hall")
      RegExp(
        r'\b(room|rm|block|hostel|hall|flat)\s+[a-z0-9-]+\b',
        caseSensitive: false,
      ): '[LOCATION]',
    };

    patterns.forEach((regex, replacement) {
      scrubbed = scrubbed.replaceAll(regex, replacement);
    });

    return scrubbed;
  }

  /// Scrubs incidental PII using both regex patterns and offline ML Kit NER.
  Future<String> scrubNarrative(String rawText) async {
    String scrubbed = scrubRegexPatterns(rawText);

    try {
      final annotations = await _entityExtractor.annotateText(scrubbed);

      for (final annotation in annotations.reversed) {
        final hasSensitiveEntity = annotation.entities.any((e) =>
            e.type == EntityType.address ||
            e.type == EntityType.phone ||
            e.type == EntityType.email);

        if (hasSensitiveEntity) {
          scrubbed = scrubbed.replaceRange(
            annotation.start,
            annotation.end,
            '[REDACTED]',
          );
        }
      }
    } on MissingPluginException {
      // Fallback to regex-scrubbed output when running on desktop/CI test VMs
    }

    return scrubbed;
  }

  Future<void> dispose() async {
    try {
      await _entityExtractor.close();
    } on MissingPluginException {
      // Ignore on desktop/CI test VMs without ML Kit platform channels
    }
  }
}