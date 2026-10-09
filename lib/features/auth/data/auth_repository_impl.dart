import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'package:uuid/uuid.dart';

import '../../../core/env.dart';
import '../../../core/failures.dart';
import '../../../core/result.dart';
import '../../../core/storage/local_store.dart';
import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

/// Supabase Auth for cloud accounts plus an on-device profile for
/// local-only mode.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required LocalStore store, SupabaseClient? client}) : _store = store, _client = client {
    _authSub = _client?.auth.onAuthStateChange.listen((_) => _emit());
  }

  final LocalStore _store;
  final SupabaseClient? _client;
  final _changes = StreamController<AppUser?>.broadcast();
  StreamSubscription<AuthState>? _authSub;

  static const _localUserKey = 'local_user';

  @override
  bool get isCloudAvailable => _client != null;

  @override
  AppUser? get currentUser {
    final cloudUser = _client?.auth.currentUser;
    if (cloudUser != null) return _map(cloudUser);
    final raw = _store.settings.get(_localUserKey);
    if (raw == null) return null;
    final j = LocalStore.decode(raw);
    return AppUser(id: j['id'] as String, displayName: j['name'] as String, isLocal: true);
  }

  @override
  Stream<AppUser?> watchUser() async* {
    yield currentUser;
    yield* _changes.stream;
  }

  void _emit() => _changes.add(currentUser);

  static AppUser _map(User u) {
    final meta = u.userMetadata ?? const {};
    final name = (meta['display_name'] ?? meta['full_name'] ?? meta['name']) as String?;
    return AppUser(
      id: u.id,
      email: u.email,
      displayName: name?.trim().isNotEmpty == true ? name!.trim() : (u.email?.split('@').first ?? 'You'),
      isLocal: false,
    );
  }

  Future<Result<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on AuthException catch (e) {
      return Failure(AuthFailure(_friendly(e.message)));
    } catch (_) {
      return const Failure(NetworkFailure('Could not reach Keepr. Check your connection.'));
    }
  }

  static String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login')) return 'Email or password is incorrect.';
    if (m.contains('already registered')) return 'An account with this email already exists.';
    if (m.contains('email not confirmed')) return 'Please confirm your email first. Check your inbox.';
    return message;
  }

  SupabaseClient? get _cloud => _client;

  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) async {
    final client = _cloud;
    if (client == null) return const Failure(CloudUnavailableFailure());
    return _guard(() async {
      final res = await client.auth.signInWithPassword(email: email, password: password);
      await _store.settings.delete(_localUserKey);
      final user = _map(res.user!);
      _emit();
      return user;
    });
  }

  @override
  Future<Result<AppUser?>> signUp({required String name, required String email, required String password}) async {
    final client = _cloud;
    if (client == null) return const Failure(CloudUnavailableFailure());
    return _guard(() async {
      final res = await client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': name},
        emailRedirectTo: kIsWeb ? null : Env.authRedirect,
      );
      if (res.session == null) return null;
      await _store.settings.delete(_localUserKey);
      _emit();
      return _map(res.user!);
    });
  }

  @override
  Future<Result<void>> signInWithGoogle() async {
    final client = _cloud;
    if (client == null) return const Failure(CloudUnavailableFailure());
    return _guard(() async {
      await client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: kIsWeb ? null : Env.authRedirect);
    });
  }

  @override
  Future<Result<void>> sendPasswordReset(String email) async {
    final client = _cloud;
    if (client == null) return const Failure(CloudUnavailableFailure());
    return _guard(() => client.auth.resetPasswordForEmail(email, redirectTo: kIsWeb ? null : Env.authRedirect));
  }

  @override
  Future<Result<AppUser>> continueOffline(String name) async {
    final user = AppUser(id: const Uuid().v4(), displayName: name, isLocal: true);
    await _store.settings.put(_localUserKey, LocalStore.encode({'id': user.id, 'name': user.displayName}));
    _emit();
    return Success(user);
  }

  @override
  Future<Result<void>> updateDisplayName(String name) async {
    final user = currentUser;
    if (user == null) return const Failure(AuthFailure('Not signed in.'));
    if (user.isLocal) {
      await _store.settings.put(_localUserKey, LocalStore.encode({'id': user.id, 'name': name}));
      _emit();
      return const Success(null);
    }
    final client = _cloud!;
    return _guard(() async {
      await client.auth.updateUser(UserAttributes(data: {'display_name': name}));
      await client.from('profiles').update({'display_name': name}).eq('id', user.id);
      _emit();
    });
  }

  @override
  Future<void> signOut() async {
    try {
      await _client?.auth.signOut();
    } catch (_) {
      // Signing out locally must work offline.
    }
    await _store.settings.delete(_localUserKey);
    await _store.clearAll();
    _emit();
  }

  @override
  Future<Result<void>> deleteAccount() async {
    final user = currentUser;
    if (user == null) return const Failure(AuthFailure('Not signed in.'));
    if (!user.isLocal) {
      final result = await _guard(() => _client!.functions.invoke('delete-account'));
      if (result case Failure(:final failure)) return Failure(failure);
    }
    await signOut();
    return const Success(null);
  }

  void dispose() {
    _authSub?.cancel();
    _changes.close();
  }
}
