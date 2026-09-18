import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseBootstrap {
  static bool _ready = false;

  static bool get isReady => _ready;

  static Future<void> initialize() async {
    if (_ready) return;

    try {
      await Firebase.initializeApp();
      _ready = true;
      debugPrint('✅ Firebase initialized');
    } catch (e, st) {
      _ready = false;
      debugPrint('⚠️ Firebase init skipped: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}
