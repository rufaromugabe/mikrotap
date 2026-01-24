import 'dart:async';

import '../models/app_user.dart';
import 'auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository();

  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;

  @override
  Stream<AppUser?> authStateChanges() {
    // Ensure each new listener immediately gets the current auth state.
    return Stream<AppUser?>.multi((multi) {
      multi.add(_current);
      final sub = _controller.stream.listen(
        multi.add,
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> signInWithGoogle() async {
    // Dev-friendly sign-in for when Firebase isn't configured yet.
    _current = const AppUser(
      uid: 'dev-user',
      email: 'dev@mikrotap.local',
      displayName: 'Developer',
    );
    _controller.add(_current);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}

