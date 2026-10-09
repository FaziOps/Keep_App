class AppUser {
  const AppUser({required this.id, required this.displayName, required this.isLocal, this.email});

  final String id;
  final String displayName;
  final String? email;

  /// True for an on-device profile without a cloud account.
  final bool isLocal;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.displayName == displayName &&
      other.email == email &&
      other.isLocal == isLocal;

  @override
  int get hashCode => Object.hash(id, displayName, email, isLocal);
}
