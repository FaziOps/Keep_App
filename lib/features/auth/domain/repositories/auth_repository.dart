import '../../../../core/result.dart';
import '../entities/app_user.dart';

abstract interface class AuthRepository {
  /// Whether a cloud backend is configured for this build.
  bool get isCloudAvailable;

  AppUser? get currentUser;
  Stream<AppUser?> watchUser();

  Future<Result<AppUser>> signIn({required String email, required String password});

  /// Returns null when the account needs email confirmation first.
  Future<Result<AppUser?>> signUp({required String name, required String email, required String password});

  Future<Result<void>> signInWithGoogle();
  Future<Result<void>> sendPasswordReset(String email);

  /// Creates an on-device profile (no cloud account).
  Future<Result<AppUser>> continueOffline(String name);

  Future<Result<void>> updateDisplayName(String name);
  Future<void> signOut();
  Future<Result<void>> deleteAccount();
}
