import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device OCR via Google ML Kit (Latin script). Turns an image file into
/// plain text fully on the phone — no network, no API key, fully private. The
/// recognized text is then handed to the AI text extractor (Claude/Codex via
/// the bridge) which already produces the structured movements.
class OcrService {
  OcrService() : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  /// A single ML Kit recognizer is not safe for overlapping `processImage`
  /// calls, and document parsing runs in the background — two uploads in flight
  /// could interleave. Serialize calls with a chained-future lock so each OCR
  /// runs to completion before the next starts.
  Future<void> _lock = Future<void>.value();

  /// Recognizes all text in the image at [path]. Returns the joined text
  /// (blocks separated by newlines), or empty when nothing is found.
  Future<String> ocrImageFile(String path) {
    final run = _lock.then((_) async {
      final input = InputImage.fromFilePath(path);
      final result = await _recognizer.processImage(input);
      return result.text;
    });
    // Keep the lock alive past this call (swallowing its result/errors) so the
    // next caller waits for this one regardless of outcome.
    _lock = run.then((_) {}, onError: (_) {});
    return run;
  }

  void dispose() => _recognizer.close();
}

final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService();
  ref.onDispose(service.dispose);
  return service;
});
