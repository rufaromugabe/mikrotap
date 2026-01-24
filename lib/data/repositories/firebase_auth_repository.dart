import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_user.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    fb.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _auth = firebaseAuth ?? fb.FirebaseAuth.instance,
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
    _googleInit ??= _googleSignIn.initialize();
    await _googleInit;

    final googleUser = await _googleSignIn.authenticate(scopeHint: const [
      'email',
      'profile',
      'openid',
    ]);

    final googleAuth = googleUser.authentication;
    final authz = await googleUser.authorizationClient.authorizeScopes(
      const ['email', 'profile', 'openid'],
    );

    final credential = fb.GoogleAuthProvider.credential(
      accessToken: authz.accessToken,
      idToken: googleAuth.idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  @override
  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }
}

