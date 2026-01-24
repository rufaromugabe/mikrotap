import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../core/config/app_config.dart';

Future<void> maybeInitializeFirebase() async {
  if (!AppConfig.firebaseEnabled) return;

  try {
    // For Android/iOS/macOS/windows/linux you can often initialize without
    // explicit options (after adding platform config files).
    //
    // For web you will typically generate `firebase_options.dart` with
    // `flutterfire configure` and initialize with options.
    await Firebase.initializeApp();
  } catch (e, st) {
    // Keep the app runnable even before Firebase config is added.
    debugPrint('Firebase init failed (FIREBASE_ENABLED=true): $e');
    debugPrintStack(stackTrace: st);
  }
}

