import '../models/app_user.dart';

abstract class AuthRepository {
  Stream<AppUser?> authStateChanges();

  Future<void> signInWithGoogle();
  Future<void> signOut();
}

