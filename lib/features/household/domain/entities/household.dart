enum MemberRole {
  owner,
  editor,
  viewer;

  static MemberRole parse(String? v) =>
      MemberRole.values.firstWhere((r) => r.name == v, orElse: () => MemberRole.viewer);

  /// BR-08.
  bool get canEdit => this == owner || this == editor;
  bool get canManageMembers => this == owner;
}

class Household {
  const Household({required this.id, required this.name, required this.role, required this.isLocal});

  final String id;
  final String name;

  /// The current user's role in this household.
  final MemberRole role;
  final bool isLocal;

  static String localIdFor(String userId) => 'local-$userId';
}

class HouseholdMember {
  const HouseholdMember({required this.userId, required this.displayName, required this.role, this.email});

  final String userId;
  final String displayName;
  final String? email;
  final MemberRole role;
}

class HouseholdInvite {
  const HouseholdInvite({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;
}
