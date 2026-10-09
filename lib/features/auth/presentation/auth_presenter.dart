import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/failures.dart';
import '../../../core/result.dart';

enum AuthMode { signIn, signUp, local }

class AuthUiState {
  const AuthUiState({
    required this.mode,
    required this.cloudAvailable,
    this.submitting = false,
    this.fieldErrors = const {},
    this.error,
    this.info,
  });

  final AuthMode mode;
  final bool cloudAvailable;
  final bool submitting;
  final Map<String, String> fieldErrors;
  final String? error;
  final String? info;

  AuthUiState copyWith({
    AuthMode? mode,
    bool? submitting,
    Map<String, String>? fieldErrors,
    String? error,
    String? info,
  }) => AuthUiState(
    mode: mode ?? this.mode,
    cloudAvailable: cloudAvailable,
    submitting: submitting ?? this.submitting,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    error: error,
    info: info,
  );
}

/// Presenter for the sign-in screen (SSD-1).
class AuthPresenter extends Notifier<AuthUiState> {
  @override
  AuthUiState build() {
    final cloud = ref.read(authRepositoryProvider).isCloudAvailable;
    return AuthUiState(mode: cloud ? AuthMode.signIn : AuthMode.local, cloudAvailable: cloud);
  }

  void setMode(AuthMode mode) => state = AuthUiState(mode: mode, cloudAvailable: state.cloudAvailable);

  Future<void> submit({required String name, required String email, required String password}) async {
    state = state.copyWith(submitting: true, fieldErrors: const {});
    switch (state.mode) {
      case AuthMode.signIn:
        _handle(await ref.read(signInProvider)(email, password));
      case AuthMode.signUp:
        final result = await ref.read(signUpProvider)(name, email, password);
        if (!ref.mounted) return;
        if (result case Success(value: null)) {
          state = const AuthUiState(
            mode: AuthMode.signIn,
            cloudAvailable: true,
            info: 'Check your inbox to confirm your email, then sign in.',
          );
          return;
        }
        _handle(result);
      case AuthMode.local:
        _handle(await ref.read(continueOfflineProvider)(name));
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(submitting: true);
    _handle(await ref.read(authRepositoryProvider).signInWithGoogle());
  }

  Future<void> resetPassword(String email) async {
    if (!email.contains('@')) {
      state = state.copyWith(fieldErrors: {'email': 'Enter your email first'});
      return;
    }
    final result = await ref.read(authRepositoryProvider).sendPasswordReset(email.trim());
    if (!ref.mounted) return;
    state = result.fold(
      (f) => state.copyWith(error: f.message),
      (_) => state.copyWith(info: 'Password reset link sent to $email.'),
    );
  }

  void _handle(Result<Object?> result) {
    if (!ref.mounted) return;
    state = switch (result) {
      Success() => state.copyWith(submitting: false),
      Failure(failure: ValidationFailure(:final fieldErrors)) => state.copyWith(
        submitting: false,
        fieldErrors: fieldErrors,
      ),
      Failure(:final failure) => state.copyWith(submitting: false, error: failure.message),
    };
  }
}

final authPresenterProvider = NotifierProvider.autoDispose<AuthPresenter, AuthUiState>(AuthPresenter.new);

/// Presenter for onboarding: records completion (FR onboarding).
class OnboardingPresenter extends Notifier<int> {
  @override
  int build() => 0;

  void setPage(int page) => state = page;

  Future<void> complete() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.save(repo.current.copyWith(onboardingDone: true));
  }
}

final onboardingPresenterProvider = NotifierProvider.autoDispose<OnboardingPresenter, int>(OnboardingPresenter.new);
