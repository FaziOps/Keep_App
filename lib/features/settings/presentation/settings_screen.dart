import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/domain/money.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../billing/domain/entities/entitlement.dart';
import '../domain/entities/app_settings.dart';
import 'settings_presenter.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsPresenterProvider);
    final presenter = ref.read(settingsPresenterProvider.notifier);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final user = state.user;
    final e = state.entitlement;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            SurfaceCard(
              onTap: () => _editName(context, presenter, user?.displayName ?? ''),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: Text(user?.initials ?? '?', style: text.titleMedium?.copyWith(color: scheme.onPrimary)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.displayName ?? '', style: text.titleMedium),
                        Text(
                          user == null
                              ? ''
                              : user.isLocal
                              ? 'Local profile on this device'
                              : user.email ?? '',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_rounded, size: 20),
                ],
              ),
            ),
            if (e != null)
              _PlanCard(
                entitlement: e,
                aiAvailable: state.cloudAvailable && !(user?.isLocal ?? true),
                onResetToFree: presenter.resetToFree,
              ),
            const SectionHeader('Sharing & sync'),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.family_restroom_rounded),
                    title: const Text('Household'),
                    subtitle: Text(
                      state.household?.isLocal ?? true
                          ? 'Sharing needs a cloud account'
                          : '${state.household!.name} · ${state.household!.role.name}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/household'),
                  ),
                  const Divider(indent: 56),
                  ListTile(
                    leading: Icon(
                      state.sync.isSyncing
                          ? Icons.sync_rounded
                          : state.sync.enabled
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                    ),
                    title: const Text('Cloud backup'),
                    subtitle: Text(_syncSubtitle(state)),
                    trailing: state.sync.enabled && !(user?.isLocal ?? true)
                        ? TextButton(
                            onPressed: state.sync.isSyncing
                                ? null
                                : () async {
                                    final message = await presenter.syncNow();
                                    if (context.mounted) showMessage(context, message);
                                  },
                            child: const Text('Sync now'),
                          )
                        : null,
                  ),
                ],
              ),
            ),
            const SectionHeader('Preferences'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Appearance', style: text.labelLarge),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemePreference>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemePreference.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_rounded),
                        ),
                        ButtonSegment(
                          value: ThemePreference.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_rounded),
                        ),
                        ButtonSegment(
                          value: ThemePreference.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_rounded),
                        ),
                      ],
                      selected: {state.settings.themePreference},
                      onSelectionChanged: (s) => presenter.setTheme(s.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: state.settings.currency,
                    decoration: const InputDecoration(
                      labelText: 'Default currency',
                      prefixIcon: Icon(Icons.currency_exchange_rounded),
                    ),
                    items: [
                      for (final c in kSupportedCurrencies)
                        DropdownMenuItem(value: c, child: Text('$c  ${currencySymbol(c)}')),
                    ],
                    onChanged: (c) => c == null ? null : presenter.setCurrency(c),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Deadline reminders'),
                    subtitle: const Text('Return windows and warranty expiry'),
                    value: state.settings.notificationsEnabled,
                    onChanged: (v) async {
                      final ok = await presenter.setNotifications(v);
                      if (!ok && context.mounted) {
                        showMessage(context, 'Allow notifications for Keepr in your device settings.', error: true);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SectionHeader('Your data'),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('Export receipts (CSV)'),
                    onTap: () async {
                      final error = await presenter.exportAll();
                      if (error != null && context.mounted) showMessage(context, error, error: true);
                    },
                  ),
                  const Divider(indent: 56),
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('Recently deleted'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/trash'),
                  ),
                  const Divider(indent: 56),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_rounded),
                    title: const Text('Add sample receipts'),
                    subtitle: const Text('Explore Keepr with demo data'),
                    onTap: () async {
                      final n = await presenter.loadSamples();
                      if (context.mounted) showMessage(context, 'Added $n sample receipts');
                    },
                  ),
                ],
              ),
            ),
            const SectionHeader('Account'),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: const Text('Sign out'),
                    onTap: () => _signOut(context, presenter, isLocal: user?.isLocal ?? true),
                  ),
                  const Divider(indent: 56),
                  ListTile(
                    leading: Icon(Icons.person_remove_rounded, color: scheme.error),
                    title: Text('Delete account', style: TextStyle(color: scheme.error)),
                    subtitle: const Text('Permanently remove your profile, receipts and images'),
                    onTap: () => _deleteAccount(context, presenter),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Keepr 1.0 · Made with Flutter',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _syncSubtitle(SettingsUiState s) {
    if (!s.cloudAvailable) return 'Not configured in this build';
    if (s.user?.isLocal ?? true) return 'Off. Sign in with an account to back up';
    if (s.sync.isSyncing) return 'Syncing…';
    if (s.sync.lastError != null) return s.sync.lastError!;
    if (s.sync.pendingOps > 0) return '${s.sync.pendingOps} changes waiting to upload';
    final last = s.sync.lastSyncedAt;
    return last == null ? 'Waiting for first sync' : 'Last synced ${timeAgo(last, DateTime.now())}';
  }

  Future<void> _editName(BuildContext context, SettingsPresenter presenter, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final error = await presenter.updateName(name);
    if (error != null && context.mounted) showMessage(context, error, error: true);
  }

  Future<void> _signOut(BuildContext context, SettingsPresenter presenter, {required bool isLocal}) async {
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      message: isLocal
          ? 'Your local profile and all receipts on this device will be removed. Export them first if you want to keep them.'
          : presenter.hasUnsyncedChanges
          ? 'Some changes have not been uploaded yet and will be lost. Sync first if you can.'
          : 'Your receipts stay safe in the cloud. You can sign in again anytime.',
      confirmLabel: 'Sign out',
      destructive: isLocal || presenter.hasUnsyncedChanges,
    );
    if (ok) await presenter.signOut();
  }

  Future<void> _deleteAccount(BuildContext context, SettingsPresenter presenter) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete your account?',
      message: 'This permanently deletes your profile, receipts, images and backups. This cannot be undone.',
      confirmLabel: 'Delete forever',
      destructive: true,
    );
    if (!ok) return;
    final error = await presenter.deleteAccount();
    if (error != null && context.mounted) showMessage(context, error, error: true);
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.entitlement, required this.aiAvailable, this.onResetToFree});
  final Entitlement entitlement;
  final bool aiAvailable;
  final VoidCallback? onResetToFree;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entitlement;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: e.isPremium
            ? const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)])
            : KeeprColors.heroGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(e.isPremium ? Icons.workspace_premium_rounded : Icons.bolt_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(e.isPremium ? 'Keepr Premium' : 'Free plan', style: text.titleMedium?.copyWith(color: Colors.white)),
              const Spacer(),
              if (!e.isPremium)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: KeeprColors.brandDeep,
                    minimumSize: const Size(0, 38),
                  ),
                  onPressed: () => context.push('/paywall'),
                  child: const Text('Upgrade'),
                )
              else if (onResetToFree != null)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.9),
                    minimumSize: const Size(0, 36),
                  ),
                  onPressed: onResetToFree,
                  child: const Text('Reset to Free'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (e.isPremium)
            Text(
              'Unlimited AI scans and claim packs${e.expiresAt == null ? '' : ' · renews ${formatDate(e.expiresAt!)}'}',
              style: text.bodySmall?.copyWith(color: Colors.white70),
            )
          else ...[
            if (aiAvailable)
              _Usage(label: 'AI scans', used: e.scansUsed, limit: PlanLimits.freeScansPerMonth)
            else
              Text(
                'Unlimited on-device scanning. Cloud AI scans need an account.',
                style: text.bodySmall?.copyWith(color: Colors.white70),
              ),
            const SizedBox(height: 10),
            _Usage(label: 'Claim packs', used: e.claimPacksUsed, limit: PlanLimits.freeClaimPacksPerMonth),
          ],
        ],
      ),
    );
  }
}

class _Usage extends StatelessWidget {
  const _Usage({required this.label, required this.used, required this.limit});
  final String label;
  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white)),
          const Spacer(),
          Text(
            '$used / $limit this month',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: (used / limit).clamp(0, 1).toDouble(),
          minHeight: 6,
          color: Colors.white,
          backgroundColor: Colors.white24,
        ),
      ),
    ],
  );
}
