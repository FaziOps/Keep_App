import '../entities/app_settings.dart';

abstract interface class SettingsRepository {
  AppSettings get current;
  Stream<AppSettings> watch();
  Future<void> save(AppSettings settings);
}
