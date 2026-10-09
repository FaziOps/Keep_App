enum ThemePreference { system, light, dark }

class AppSettings {
  const AppSettings({
    this.themePreference = ThemePreference.system,
    this.currency = 'PKR',
    this.notificationsEnabled = true,
    this.onboardingDone = false,
    this.activeHouseholdId,
  });

  final ThemePreference themePreference;
  final String currency;
  final bool notificationsEnabled;
  final bool onboardingDone;
  final String? activeHouseholdId;

  AppSettings copyWith({
    ThemePreference? themePreference,
    String? currency,
    bool? notificationsEnabled,
    bool? onboardingDone,
    String? activeHouseholdId,
    bool clearActiveHousehold = false,
  }) => AppSettings(
    themePreference: themePreference ?? this.themePreference,
    currency: currency ?? this.currency,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    onboardingDone: onboardingDone ?? this.onboardingDone,
    activeHouseholdId: clearActiveHousehold ? null : activeHouseholdId ?? this.activeHouseholdId,
  );
}
