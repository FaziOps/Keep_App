import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failures.dart';
import '../../../core/result.dart';
import '../../../core/storage/local_store.dart';
import '../../auth/domain/entities/app_user.dart';
import '../domain/entities/household.dart';
import '../domain/repositories/household_repository.dart';

class HouseholdRepositoryImpl implements HouseholdRepository {
  const HouseholdRepositoryImpl({required LocalStore store, SupabaseClient? client}) : _store = store, _client = client;

  final LocalStore _store;
  final SupabaseClient? _client;

  static Household _localFor(AppUser user) =>
      Household(id: Household.localIdFor(user.id), name: 'My vault', role: MemberRole.owner, isLocal: true);

  String _cacheKey(String userId) => 'households:$userId';

  @override
  Future<Result<List<Household>>> households(AppUser user) async {
    final client = _client;
    if (user.isLocal || client == null) return Success([_localFor(user)]);
    try {
      final rows = await client.from('household_members').select('role, households(id, name)').eq('user_id', user.id);
      final list = [
        for (final row in rows)
          Household(
            id: (row['households'] as Map)['id'] as String,
            name: (row['households'] as Map)['name'] as String,
            role: MemberRole.parse(row['role'] as String?),
            isLocal: false,
          ),
      ];
      await _store.meta.put(
        _cacheKey(user.id),
        jsonEncode([
          for (final h in list) {'id': h.id, 'name': h.name, 'role': h.role.name},
        ]),
      );
      return Success(list);
    } catch (_) {
      final cached = _store.meta.get(_cacheKey(user.id));
      if (cached == null) return const Failure(NetworkFailure());
      return Success([
        for (final raw in jsonDecode(cached) as List)
          Household(
            id: (raw as Map)['id'] as String,
            name: raw['name'] as String,
            role: MemberRole.parse(raw['role'] as String?),
            isLocal: false,
          ),
      ]);
    }
  }

  @override
  Future<Result<Household>> activeHousehold(AppUser user, {String? preferredId}) async {
    final result = await households(user);
    return result.fold(Failure.new, (list) {
      if (list.isEmpty) {
        return const Failure(NotFoundFailure('No household found for this account.'));
      }
      final preferred = list.where((h) => h.id == preferredId);
      if (preferred.isNotEmpty) return Success(preferred.first);
      final owned = list.where((h) => h.role == MemberRole.owner);
      return Success(owned.isNotEmpty ? owned.first : list.first);
    });
  }

  @override
  Future<Result<List<HouseholdMember>>> members(String householdId) async {
    final client = _client;
    if (client == null || householdId.startsWith('local-')) {
      return const Failure(CloudUnavailableFailure());
    }
    try {
      final rows = await client
          .from('household_members')
          .select('user_id, role, profiles(display_name, email)')
          .eq('household_id', householdId);
      return Success(
        [
          for (final row in rows)
            HouseholdMember(
              userId: row['user_id'] as String,
              role: MemberRole.parse(row['role'] as String?),
              displayName: ((row['profiles'] as Map?)?['display_name'] as String?) ?? 'Member',
              email: (row['profiles'] as Map?)?['email'] as String?,
            ),
        ]..sort((a, b) => a.role.index.compareTo(b.role.index)),
      );
    } catch (_) {
      return const Failure(NetworkFailure());
    }
  }

  @override
  Future<Result<HouseholdInvite>> createInvite({
    required String householdId,
    required String email,
    required MemberRole role,
  }) async {
    final client = _client;
    if (client == null || householdId.startsWith('local-')) {
      return const Failure(CloudUnavailableFailure());
    }
    try {
      final res = await client.rpc<dynamic>(
        'create_household_invite',
        params: {'p_household_id': householdId, 'p_email': email.trim().toLowerCase(), 'p_role': role.name},
      );
      final map = (res as Map).cast<String, dynamic>();
      return Success(
        HouseholdInvite(code: map['code'] as String, expiresAt: DateTime.parse(map['expires_at'] as String).toLocal()),
      );
    } on PostgrestException catch (e) {
      if (e.message.contains('member_limit')) {
        return const Failure(QuotaExceeded(QuotaKind.householdMember));
      }
      return Failure(PermissionFailure(e.message));
    } catch (_) {
      return const Failure(NetworkFailure());
    }
  }

  @override
  Future<Result<String>> acceptInvite(String code) async {
    final client = _client;
    if (client == null) return const Failure(CloudUnavailableFailure());
    try {
      final id = await client.rpc<dynamic>('accept_household_invite', params: {'p_code': code.trim().toUpperCase()});
      return Success(id as String);
    } on PostgrestException catch (e) {
      final m = e.message;
      if (m.contains('invalid_invite')) {
        return const Failure(ValidationFailure({'code': 'This code is invalid or has expired'}));
      }
      if (m.contains('member_limit')) return const Failure(QuotaExceeded(QuotaKind.householdMember));
      return Failure(PermissionFailure(m));
    } catch (_) {
      return const Failure(NetworkFailure());
    }
  }

  @override
  Future<Result<void>> removeMember(String householdId, String userId) async {
    final client = _client;
    if (client == null) return const Failure(CloudUnavailableFailure());
    try {
      await client.from('household_members').delete().match({'household_id': householdId, 'user_id': userId});
      return const Success(null);
    } on PostgrestException catch (e) {
      return Failure(PermissionFailure(e.message));
    } catch (_) {
      return const Failure(NetworkFailure());
    }
  }
}
