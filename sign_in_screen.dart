import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/common.dart';
import 'auth_presenter.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() =>
      ref.read(authPresenterProvider.notifier).submit(name: _name.text, email: _email.text, password: _password.text);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authPresenterProvider);
    final presenter = ref.read(authPresenterProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    ref.listen(authPresenterProvider.select((s) => s.error), (_, error) {
      if (error != null) showMessage(context, error, error: true);
    });

    final title = switch (state.mode) {
      AuthMode.signIn => 'Welcome back',
      AuthMode.signUp => 'Create your vault',
      AuthMode.local => 'Start on this device',
    };
    final subtitle = switch (state.mode) {
      AuthMode.signIn => 'Sign in to sync your receipts across devices.',
      AuthMode.signUp => 'Back up receipts, scan with AI and share with family.',
      AuthMode.local => 'Your receipts stay on this device. You can create a cloud account later.',
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status bar icons over the gradient header.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: KeeprColors.heroGradient,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
                ),
                padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 28, 24, 36),
                child: ContentWidth(
                  maxWidth: 480,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Keepr',
                            style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Text(title, style: text.headlineMedium?.copyWith(color: Colors.white)),
                      const SizedBox(height: 8),
                      Text(subtitle, style: text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: ContentWidth(
                maxWidth: 480,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.cloudAvailable) ...[
                          SegmentedButton<AuthMode>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: AuthMode.signIn, label: Text('Sign in')),
                              ButtonSegment(value: AuthMode.signUp, label: Text('Sign up')),
                            ],
                            selected: {state.mode == AuthMode.local ? AuthMode.signIn : state.mode},
                            onSelectionChanged: (s) => presenter.setMode(s.first),
                          ),
                          const SizedBox(height: 20),
                        ] else
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.phone_iphone_rounded, color: scheme.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Local mode: receipts are read on your phone. Add Supabase keys for cloud backup, sharing and cloud AI.',
                                    style: text.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (state.info != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Pill(
                              label: state.info!,
                              color: KeeprColors.success,
                              icon: Icons.mark_email_read_rounded,
                            ),
                          ),
                        if (state.mode != AuthMode.signIn) ...[
                          TextField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            decoration: InputDecoration(
                              labelText: 'Your name',
                              prefixIcon: const Icon(Icons.person_outline_rounded),
                              errorText: state.fieldErrors['name'],
                            ),
                            onSubmitted: state.mode == AuthMode.local ? (_) => _submit() : null,
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (state.mode != AuthMode.local) ...[
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: const Icon(Icons.alternate_email_rounded),
                              errorText: state.fieldErrors['email'],
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _password,
                            obscureText: _obscure,
                            autofillHints: [
                              state.mode == AuthMode.signUp ? AutofillHints.newPassword : AutofillHints.password,
                            ],
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              errorText: state.fieldErrors['password'],
                              helperText: state.mode == AuthMode.signUp ? 'At least 8 characters with a number' : null,
                              suffixIcon: IconButton(
                                tooltip: _obscure ? 'Show password' : 'Hide password',
                                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          if (state.mode == AuthMode.signIn)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => presenter.resetPassword(_email.text),
                                child: const Text('Forgot password?'),
                              ),
                            )
                          else
                            const SizedBox(height: 14),
                        ],
                        const SizedBox(height: 8),
                        LoadingButton(
                          label: switch (state.mode) {
                            AuthMode.signIn => 'Sign in',
                            AuthMode.signUp => 'Create account',
                            AuthMode.local => 'Continue',
                          },
                          loading: state.submitting,
                          onPressed: _submit,
                        ),
                        if (state.cloudAvailable && state.mode != AuthMode.local) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('or', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: state.submitting ? null : presenter.signInWithGoogle,
                            icon: const Text(
                              'G',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF4285F4)),
                            ),
                            label: const Text('Continue with Google'),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => presenter.setMode(AuthMode.local),
                            child: const Text('Use without an account'),
                          ),
                        ],
                        if (state.cloudAvailable && state.mode == AuthMode.local)
                          TextButton(
                            onPressed: () => presenter.setMode(AuthMode.signIn),
                            child: const Text('I want cloud backup instead'),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'By continuing you agree to keep your receipts safe with Keepr. We never sell your data.',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
