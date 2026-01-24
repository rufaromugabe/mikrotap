# mikrotap

MikroTap is a MikroTicket-style hotspot voucher manager targeting **zero-touch provisioning** for MikroTik RouterOS hotspots.

## Quick start (runs without Firebase)

```bash
flutter pub get
flutter run
```

By default, the app runs in **dev auth mode** (a local fake sign-in) so you can start building UI and flows immediately.

## Enable Firebase (Google Sign-In + Firestore)

1) Create a Firebase project and enable:
- Authentication (Google)
- Firestore
- Storage (later)
- Functions (later)

2) Configure FlutterFire (recommended):

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

3) Run with Firebase enabled:

```bash
flutter run --dart-define=FIREBASE_ENABLED=true
```

## Project structure (high level)

- `lib/app/`: app entry (router + theme)
- `lib/core/`: config, utilities, shared errors/constants
- `lib/data/`: models, repositories, services (Firebase, MikroTik, etc.)
- `lib/presentation/`: screens, widgets, Riverpod providers
