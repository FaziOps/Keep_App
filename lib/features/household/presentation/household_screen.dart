import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/failures.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../domain/entities/household.dart';
import 'household_presenter.dart';

class HouseholdScreen extends ConsumerWidget {
  const HouseholdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(householdPresenterProvider);

    ref.listen(householdPresenterProvider.select((s) => s.value?.message), (_, message) {
      if (message != null) showMessage(context, message, error: true);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Household')),
      body: switch (async) {
        AsyncData(:final value) when value.isLocal => const EmptyState(
          icon: Icons.family_restroom_rounded,
          title: 'Share your vault with family',
          message: 'Sharing needs a Keepr cloud account. Sign out and create an account to invite family members.',
        ),
        AsyncData(:final value) => _Body(state: value),
        AsyncError(:final error) => ErrorState(
          message: error is AppFailure ? error.message : 'Could not load your household.',
          onRetry: () => ref.invalidate(householdPresenterProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.state});
  final HouseholdUiState state;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  MemberRole _role = MemberRole.editor;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final presenter = ref.read(householdPresenterProvider.notifier);
    final text = Theme.of(context).textTheme;

    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (s.households.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: s.household.id,
              decoration: const InputDecoration(labelText: 'Active vault', prefixIcon: Icon(Icons.swap_horiz_rounded)),
              items: [for (final h in s.households) DropdownMenuItem(value: h.id, child: Text(h.name))],
              onChanged: (id) => id == null ? null : presenter.switchTo(id),
            ),
            const SizedBox(height: 8),
          ],
          SectionHeader('${s.household.name} · ${s.members.length} members'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, m) in s.members.indexed) ...[
                  if (i > 0) const Divider(indent: 72),
                  ListTile(
                    leading: CircleAvatar(child: Text(m.displayName.isEmpty ? '?' : m.displayName[0].toUpperCase())),
                    title: Text(m.displayName),
                    subtitle: Text(m.email ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Pill(
                          label: m.role.name,
                          color: m.role == MemberRole.owner ? KeeprColors.brand : KeeprColors.sky,
                          dense: true,
                        ),
                        if (s.canManage && m.role != MemberRole.owner)
                          IconButton(
                            tooltip: 'Remove member',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Remove ${m.displayName}?',
                                message: 'They will lose access to this vault immediately.',
                                confirmLabel: 'Remove',
                                destructive: true,
                              );
                              if (ok) await presenter.remove(m);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (s.canManage) ...[
            const SectionHeader('Invite someone'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Their email',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<MemberRole>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: MemberRole.editor, label: Text('Can edit')),
                      ButtonSegment(value: MemberRole.viewer, label: Text('View only')),
                    ],
                    selected: {_role},
                    onSelectionChanged: (r) => setState(() => _role = r.first),
                  ),
                  const SizedBox(height: 12),
                  LoadingButton(
                    label: 'Create invite code',
                    loading: s.busy,
                    onPressed: () => presenter.invite(_email.text, _role),
                  ),
                  if (s.invite != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: KeeprColors.brand.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text('Share this code', style: text.labelLarge),
                          const SizedBox(height: 6),
                          SelectableText(s.invite!.code, style: text.headlineMedium?.copyWith(letterSpacing: 6)),
                          Text('Valid until ${formatDateTime(s.invite!.expiresAt)}', style: text.bodySmall),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: s.invite!.code));
                              showMessage(context, 'Code copied');
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy code'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SectionHeader('Join a household'),
          SurfaceCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: 'Invite code', errorText: s.codeError),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: s.busy ? null : () => presenter.join(_code.text),
                    child: const Text('Join'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
