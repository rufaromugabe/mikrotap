# Firebase Setup Guide

This guide will help you set up Firebase Authentication and other Firebase services for the MikroTap app.

## Prerequisites

1. **Firebase Account**: Create a free account at [Firebase Console](https://console.firebase.google.com/)
2. **FlutterFire CLI**: Already installed (version 1.3.1)

## Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project" or select an existing project
3. Follow the setup wizard:
   - Enter project name (e.g., "mikrotap")
   - Enable/disable Google Analytics (optional)
   - Click "Create project"

## Step 2: Enable Firebase Services

In your Firebase project console, enable the following services:

### Authentication
1. Go to **Authentication** → **Get started**
2. Click **Sign-in method** tab
3. Enable **Google** sign-in provider:
   - Click on Google
   - Toggle "Enable"
   - Add your project's support email
   - Click "Save"

### Firestore Database
1. Go to **Firestore Database** → **Create database**
2. Choose **Start in test mode** (for development)
3. Select a location for your database
4. Click "Enable"

### (Optional) Other Services
- **Storage**: For file uploads (if needed later)
- **Functions**: For server-side logic (if needed later)

## Step 3: Configure FlutterFire CLI

Run the following command in your project directory:

```bash
flutterfire configure
```

This interactive command will:
1. Ask you to log in to Firebase (if not already logged in)
2. List your Firebase projects - select the one you created
3. Ask which platforms to configure:
   - ✅ **Android** (required)
   - ✅ **iOS** (if developing for iOS)
   - ✅ **Web** (if developing for web)
   - ✅ **macOS** (if developing for macOS)
   - ✅ **Windows** (if developing for Windows)

4. Generate `lib/firebase_options.dart` with your project configuration

## Step 4: Update Firebase Initialization

After running `flutterfire configure`, update `lib/data/services/firebase_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';  // Add this import

import '../../core/config/app_config.dart';

Future<void> maybeInitializeFirebase() async {
  if (!AppConfig.firebaseEnabled) return;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,  // Use generated options
    );
  } catch (e, st) {
    debugPrint('Firebase init failed (FIREBASE_ENABLED=true): $e');
    debugPrintStack(stackTrace: st);
  }
}
```

## Step 5: Platform-Specific Setup

### Android
The `google-services.json` file should be automatically added to `android/app/` by `flutterfire configure`.

If not, manually:
1. Download `google-services.json` from Firebase Console
2. Place it in `android/app/`
3. Ensure `android/app/build.gradle.kts` includes:
   ```kotlin
   plugins {
       id("com.google.gms.google-services")
   }
   ```

### iOS
The `GoogleService-Info.plist` should be automatically added to `ios/Runner/` by `flutterfire configure`.

If not, manually:
1. Download `GoogleService-Info.plist` from Firebase Console
2. Add it to `ios/Runner/` in Xcode
3. Ensure it's added to the Runner target

### Web
The Firebase config will be in `firebase_options.dart`. No additional setup needed.

## Step 6: Test Firebase Connection

Run the app with Firebase enabled:

```bash
flutter run --dart-define=FIREBASE_ENABLED=true
```

Or set it permanently in your IDE run configuration:
- **Dart defines**: `FIREBASE_ENABLED=true`

## Troubleshooting

### "Firebase init failed" error
- Check that `firebase_options.dart` exists in `lib/`
- Verify you've enabled Authentication in Firebase Console
- Ensure platform config files are in place (google-services.json, GoogleService-Info.plist)

### Google Sign-In not working
- Verify Google sign-in is enabled in Firebase Console
- Check that OAuth consent screen is configured in Google Cloud Console
- Ensure SHA-1 fingerprint is added for Android (if needed)

### Firestore permission errors
- Check Firestore security rules
- For development, you can use test mode rules temporarily

## Next Steps

After setup:
1. Test Google Sign-In in the app
2. Verify user plans are saved to Firestore
3. Check router data is being saved correctly
4. Set up proper Firestore security rules for production

## Security Rules Example

For development, you can use these rules in Firestore:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their own data
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

For production, implement more restrictive rules based on your needs.
