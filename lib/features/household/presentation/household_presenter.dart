import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/failures.dart';
import '../../../core/result.dart';
import '../domain/entities/household.dart';

class HouseholdUiState {
  const HouseholdUiState({
    required this.household,
    this.members = const [],
    this.households = const [],
    this.invite,
    this.busy = false,
    this.message,
    this.codeError,
  });

  final Household household;
  final List<HouseholdMember> members;
  final List<Household> households;
  final HouseholdInvite? invite;
  final bool busy;
  final String? message;
  final String? codeError;

  bool get isLocal => household.isLocal;
  bool get canManage => household.role.canManageMembers;

  HouseholdUiState copyWith({
    List<HouseholdMember>? members,
    HouseholdInvite? invite,
    bool? busy,
    String? message,
    String? codeError,
  }) => HouseholdUiState(
    household: household,
    members: members ?? this.members,
    households: households,
    invite: invite ?? this.invite,
    busy: busy ?? this.busy,
    message: message,
    codeError: codeError,
  );
}

/// Presenter for household sharing (FR-HH-01..04, BR-08).
class HouseholdPresenter extends AsyncNotifier<HouseholdUiState> {
  @override
  Future<HouseholdUiState> build() async {
    final household = await ref.watch(activeHouseholdProvider.future);
    final user = ref.read(currentUserProvider).value;
    if (household == null || user == null) throw const AuthFailure('Not signed in.');
    if (household.isLocal) return HouseholdUiState(household: household);
    final repo = ref.read(householdRepositoryProvider);
    final members = await repo.members(household.id);
    final households = await repo.households(user);
    return HouseholdUiState(
      household: household,
      members: members.valueOrNull ?? const [],
      households: households.valueOrNull ?? [household],
    );
  }

  Future<void> invite(String email, MemberRole role) async {
    final s = state.value;
    if (s == null) return;
    if (!email.contains('@')) {
      state = AsyncData(s.copyWith(message: 'Enter a valid email'));
      return;
    }
    if (s.members.length >= (ref.read(entitlementProvider).value?.maxHouseholdMembers ?? 2)) {
      state = AsyncData(s.copyWith(message: 'Your plan’s member limit is reached. Upgrade for up to 6 members.'));
      return;
    }
    state = AsyncData(s.copyWith(busy: true));
    final result = await ref
        .read(householdRepositoryProvider)
        .createInvite(householdId: s.household.id, email: email, role: role);
    if (!ref.mounted) return;
    state = AsyncData(switch (result) {
      Success(:final value) => s.copyWith(busy: false, invite: value),
      Failure(:final failure) => s.copyWith(busy: false, message: failure.message),
    });
  }

  Future<void> join(String code) async {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(s.copyWith(busy: true));
    final result = await ref.read(householdRepositoryProvider).acceptInvite(code);
    if (!ref.mounted) return;
    switch (result) {
      case Success(:final value):
        await switchTo(value);
      case Failure(failure: ValidationFailure(:final fieldErrors)):
        state = AsyncData(s.copyWith(busy: false, codeError: fieldErrors['code']));
      case Failure(:final failure):
        state = AsyncData(s.copyWith(busy: false, message: failure.message));
    }
  }

  Future<void> switchTo(String householdId) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.save(repo.current.copyWith(activeHouseholdId: householdId));
    ref.read(syncRepositoryProvider).requestSync();
  }

  Future<void> remove(HouseholdMember member) async {
    final s = state.value;
    if (s == null) return;
    final result = await ref.read(householdRepositoryProvider).removeMember(s.household.id, member.userId);
    if (!ref.mounted) return;
    if (result is Failure) {
      state = AsyncData(s.copyWith(message: result.failureOrNull!.message));
    } else {
      ref.invalidateSelf();
    }
  }
}

final householdPresenterProvider = AsyncNotifierProvider.autoDispose<HouseholdPresenter, HouseholdUiState>(
  HouseholdPresenter.new,
);
