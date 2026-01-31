import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_user.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    fb.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  }) : _auth = firebaseAuth ?? fb.FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  static Future<void>? _googleInit;

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.authStateChanges().map((u) {
      if (u == null) return null;
      return AppUser(
        uid: u.uid,
        email: u.email,
        displayName: u.displayName,
        photoUrl: u.photoURL,
      );
    });
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      // Initialize Google Sign-In (required for version 7.0.0+)
      _googleInit ??= _googleSignIn.initialize();
      await _googleInit;

      // Trigger the authentication flow
      final googleUser = await _googleSignIn.authenticate(
        scopeHint: const ['email', 'profile', 'openid'],
      );

      // Obtain the auth details from the request
      final googleAuth = await googleUser.authentication;

      // Create a new credential
      final credential = fb.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      await _auth.signInWithCredential(credential);
    } catch (e) {
      // Re-throw to allow UI to handle the error
      throw Exception('Google sign-in failed: $e');
    }
  }

  @override
  Future<void> signOut() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }
}
