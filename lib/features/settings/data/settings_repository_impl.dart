import '../../../core/storage/local_store.dart';
import '../domain/entities/app_settings.dart';
import '../domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl(this._store);
  final LocalStore _store;

  static const _key = 'app_settings';

  @override
  AppSettings get current {
    final raw = _store.settings.get(_key);
    if (raw == null) return const AppSettings();
    final j = LocalStore.decode(raw);
    return AppSettings(
      themePreference: ThemePreference.values.byName(j['theme'] as String? ?? 'system'),
      currency: j['currency'] as String? ?? 'PKR',
      notificationsEnabled: j['notifications'] as bool? ?? true,
      onboardingDone: j['onboarding_done'] as bool? ?? false,
      activeHouseholdId: j['active_household_id'] as String?,
    );
  }

  @override
  Stream<AppSettings> watch() => watchBox(_store.settings, () => current);

  @override
  Future<void> save(AppSettings s) => _store.settings.put(
    _key,
    LocalStore.encode({
      'theme': s.themePreference.name,
      'currency': s.currency,
      'notifications': s.notificationsEnabled,
      'onboarding_done': s.onboardingDone,
      'active_household_id': s.activeHouseholdId,
    }),
  );
}
