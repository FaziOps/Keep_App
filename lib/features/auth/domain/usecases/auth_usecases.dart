import '../../../../core/failures.dart';
import '../../../../core/result.dart';
import '../entities/app_user.dart';
import '../repositories/auth_repository.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

Map<String, String> validateCredentials({required String email, required String password, String? name}) {
  final errors = <String, String>{};
  if (name != null && name.trim().length < 2) errors['name'] = 'Enter your name';
  if (!_emailPattern.hasMatch(email.trim())) errors['email'] = 'Enter a valid email';
  if (password.length < 8 || !password.contains(RegExp(r'\d'))) {
    errors['password'] = 'At least 8 characters with a number';
  }
  return errors;
}

class SignIn {
  const SignIn(this._repo);
  final AuthRepository _repo;

  Future<Result<AppUser>> call(String email, String password) async {
    if (!_emailPattern.hasMatch(email.trim())) {
      return const Failure(ValidationFailure({'email': 'Enter a valid email'}));
    }
    if (password.isEmpty) {
      return const Failure(ValidationFailure({'password': 'Enter your password'}));
    }
    return _repo.signIn(email: email.trim(), password: password);
  }
}

class SignUp {
  const SignUp(this._repo);
  final AuthRepository _repo;

  Future<Result<AppUser?>> call(String name, String email, String password) async {
    final errors = validateCredentials(email: email, password: password, name: name);
    if (errors.isNotEmpty) return Failure(ValidationFailure(errors));
    return _repo.signUp(name: name.trim(), email: email.trim(), password: password);
  }
}

class ContinueOffline {
  const ContinueOffline(this._repo);
  final AuthRepository _repo;

  Future<Result<AppUser>> call(String name) async {
    if (name.trim().length < 2) {
      return const Failure(ValidationFailure({'name': 'Enter your name'}));
    }
    return _repo.continueOffline(name.trim());
  }
}
