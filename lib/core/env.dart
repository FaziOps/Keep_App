/// Build-time configuration, passed with `--dart-define-from-file=env.json`.
///
/// When the Supabase values are empty Keepr runs in local-only mode: every
/// feature works on the device, but there is no cloud backup, sync, sharing
/// or AI extraction.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isCloudConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Deep link used by OAuth on Android and iOS.
  static const authRedirect = 'io.keepr.app://login-callback';
}
