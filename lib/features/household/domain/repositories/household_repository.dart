import '../../../../core/result.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../entities/household.dart';

abstract interface class HouseholdRepository {
  /// The household whose vault is shown, resolved for [user].
  Future<Result<Household>> activeHousehold(AppUser user, {String? preferredId});

  Future<Result<List<Household>>> households(AppUser user);
  Future<Result<List<HouseholdMember>>> members(String householdId);
  Future<Result<HouseholdInvite>> createInvite({
    required String householdId,
    required String email,
    required MemberRole role,
  });

  /// Joins a household; returns its id.
  Future<Result<String>> acceptInvite(String code);
  Future<Result<void>> removeMember(String householdId, String userId);
}
