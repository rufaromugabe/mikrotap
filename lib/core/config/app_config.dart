class AppConfig {
  /// Set to `true` when you've configured Firebase (via `flutterfire configure`)
  /// and added the required platform files (e.g. `google-services.json`).
  ///
  /// Run with:
  /// `flutter run --dart-define=FIREBASE_ENABLED=true`
  static const bool firebaseEnabled = bool.fromEnvironment(
    'FIREBASE_ENABLED',
    defaultValue: true,
  );
}
