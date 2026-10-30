import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/validators.dart';
import '../../data/repositories/auth_repository.dart';
import '../../shared/brand/brand_widgets.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import 'auth_scaffold.dart';

enum AuthPage { onboarding, welcome, citizenLogin, citizenRegister, adminLogin, adminSetup }

/// Everything shown while nobody is signed in. The page is a piece of state
/// (not a pushed route), so when sign-in succeeds the app simply swaps this
/// widget for the signed-in shell and nothing is left on the back stack.
class AuthFlow extends ConsumerStatefulWidget {
  const AuthFlow({super.key});
  @override
  ConsumerState<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends ConsumerState<AuthFlow> {
  late AuthPage _page =
      ref.read(onboardedProvider) ? AuthPage.welcome : AuthPage.onboarding;

  void _go(AuthPage p) => setState(() => _page = p);

  @override
  Widget build(BuildContext context) {
    final body = switch (_page) {
      AuthPage.onboarding => _Onboarding(onDone: () {
          ref.read(prefsProvider).setBool('onboarded', true);
          ref.read(onboardedProvider.notifier).state = true;
          _go(AuthPage.welcome);
        }),
      AuthPage.welcome => _Welcome(
          onCitizen: () => _go(AuthPage.citizenLogin),
          onAdmin: () => _go(AuthPage.adminLogin)),
      AuthPage.citizenLogin => _SignInForm(
          key: const ValueKey('citizen-login'),
          admin: false,
          onBack: () => _go(AuthPage.welcome),
          onSwitch: () => _go(AuthPage.citizenRegister)),
      AuthPage.citizenRegister => _CitizenRegisterForm(
          key: const ValueKey('citizen-register'),
          onBack: () => _go(AuthPage.citizenLogin)),
      AuthPage.adminLogin => _SignInForm(
          key: const ValueKey('admin-login'),
          admin: true,
          onBack: () => _go(AuthPage.welcome),
          onSwitch: () => _go(AuthPage.adminSetup)),
      AuthPage.adminSetup => _AdminSetupForm(
          key: const ValueKey('admin-setup'), onBack: () => _go(AuthPage.adminLogin)),
    };
    return PopScope(
      canPop: _page == AuthPage.welcome || _page == AuthPage.onboarding,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _go(switch (_page) {
          AuthPage.citizenRegister => AuthPage.citizenLogin,
          AuthPage.adminSetup => AuthPage.adminLogin,
          _ => AuthPage.welcome,
        });
      },
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: body),
    );
  }
}

// ----------------------------------------------------------------- onboarding

class _Onboarding extends StatefulWidget {
  const _Onboarding({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final _ctrl = PageController();
  int _i = 0;

  static const _pages = [
    (Icons.add_a_photo_outlined, 'Report in seconds',
        'Photograph a pothole, flooded road, broken streetlight or waste dump. Your phone\'s GPS fills in where it is.'),
    (Icons.timeline, 'Follow every step',
        'Each report moves from Submitted to Assigned, In Progress and Resolved. You are notified at every change.'),
    (Icons.lock_outline, 'Your documents stay yours',
        'Keep IDs and bills in a private vault, encrypted on this phone and visible only to you.'),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _pages.length - 1;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: widget.onDone, child: const Text('Skip')),
          ),
          Expanded(
            child: PageView.builder(
              controller: _ctrl,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) {
                final p = _pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primary.withValues(alpha: 0.12)),
                      child: Icon(p.$1, size: 56, color: scheme.primary),
                    ),
                    const SizedBox(height: 32),
                    Text(p.$2,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(p.$3,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                width: i == _i ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: i == _i ? scheme.primary : scheme.outlineVariant),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: last
                    ? widget.onDone
                    : () => _ctrl.nextPage(
                        duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(last ? 'Get started' : 'Next'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------------- welcome

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onCitizen, required this.onAdmin});
  final VoidCallback onCitizen, onAdmin;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      photo: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Welcome', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Choose how you want to sign in.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        GradientButton(onPressed: onCitizen, icon: Icons.person_outline, label: 'Citizen Login'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAdmin,
          icon: const Icon(Icons.admin_panel_settings_outlined),
          label: const Text('Administrator Login'),
        ),
        const SizedBox(height: 16),
        Text(
          'Administrator and officer accounts are issued by the city administrator. '
          'Citizens can register themselves.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- common bits

class _PasswordField extends StatefulWidget {
  const _PasswordField(
      {required this.controller, this.label = 'Password', this.validator, this.onSubmit});
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmit;
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hide = true;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _hide,
        autofillHints: const [AutofillHints.password],
        textInputAction: widget.onSubmit == null ? TextInputAction.next : TextInputAction.done,
        onFieldSubmitted: (_) => widget.onSubmit?.call(),
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _hide ? 'Show password' : 'Hide password',
            icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _hide = !_hide),
          ),
        ),
        validator: widget.validator,
      );
}

Future<void> _forgotPassword(BuildContext context, WidgetRef ref,
    {required bool admin, String email = ''}) {
  if (ref.read(authRepositoryProvider).usesEmailReset) {
    return _emailReset(context, ref, email);
  }
  return _localForgot(context, admin: admin);
}

Future<void> _emailReset(BuildContext context, WidgetRef ref, String email) async {
  final c = TextEditingController(text: email.trim());
  final send = await showDialog<bool>(
    context: context,
    builder: (x) => AlertDialog(
      icon: const Icon(Icons.lock_reset),
      title: const Text('Reset your password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('We will email you a link to choose a new password.'),
        const SizedBox(height: 12),
        TextField(
          controller: c,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Send link')),
      ],
    ),
  );
  final addr = c.text;
  c.dispose();
  if (send != true) return;
  try {
    await ref.read(authRepositoryProvider).sendPasswordReset(addr);
    if (context.mounted) {
      showMessage(context, 'If that email has an account, a reset link is on its way. Check spam too.');
    }
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}

Future<void> _localForgot(BuildContext context, {required bool admin}) => showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.lock_reset),
        title: const Text('Forgot your password?'),
        content: Text(admin
            ? 'Accounts on this build are stored on this phone, and no email can be sent '
                'from it, so a reset link is not possible yet. Another administrator can set a '
                'new password for you under Manage → Users → Reset password.\n\n'
                'Email reset and account verification arrive with the cloud sign-in stage.'
            : 'Accounts on this build are stored on this phone, and no email can be sent '
                'from it, so a reset link is not possible yet. Ask your municipal administrator '
                'to set a new password for you (Manage → Users → Reset password).\n\n'
                'Email reset and account verification arrive with the cloud sign-in stage.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );

// ------------------------------------------------------------------- sign in

class _SignInForm extends ConsumerStatefulWidget {
  const _SignInForm(
      {super.key, required this.admin, required this.onBack, required this.onSwitch});
  final bool admin;
  final VoidCallback onBack, onSwitch;
  @override
  ConsumerState<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends ConsumerState<_SignInForm> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).signIn(_email.text, _password.text,
          audience: widget.admin ? SignInAudience.staff : SignInAudience.citizen);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.admin;
    final needsSetup = admin && (ref.watch(needsSetupProvider).valueOrNull ?? false);
    final scheme = Theme.of(context).colorScheme;
    return AuthScaffold(
      onBack: widget.onBack,
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(admin ? 'Administrator sign in' : 'Welcome back',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
              admin
                  ? 'For authorised administrators and municipal officers.'
                  : 'Sign in to report issues and follow their progress.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration:
                const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
            validator: Validators.email,
          ),
          const SizedBox(height: 12),
          _PasswordField(
            controller: _password,
            onSubmit: _submit,
            validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _forgotPassword(context, ref, admin: admin, email: _email.text),
              child: const Text('Forgot password?'),
            ),
          ),
          GradientButton(
            onPressed: _submit,
            busy: _busy,
            label: 'Sign in',
          ),
          const SizedBox(height: 4),
          if (!admin)
            TextButton(
              onPressed: _busy ? null : widget.onSwitch,
              child: const Text('New here? Register'),
            ),
          if (needsSetup) ...[
            const Divider(height: 28),
            Text(
              'No administrator exists on this phone yet. Whoever sets up the app creates the '
              'first one; it is the only account that can add officers.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : widget.onSwitch,
              child: const Text('First-time setup'),
            ),
          ],
        ]),
      ),
    );
  }
}

// -------------------------------------------------------- citizen registration

class _CitizenRegisterForm extends ConsumerStatefulWidget {
  const _CitizenRegisterForm({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  ConsumerState<_CitizenRegisterForm> createState() => _CitizenRegisterFormState();
}

class _CitizenRegisterFormState extends ConsumerState<_CitizenRegisterForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).register(_name.text, _email.text, _password.text);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      onBack: widget.onBack,
      compact: true,
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Create citizen account', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Register to report and track issues in your area.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
            validator: Validators.name,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration:
                const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
            validator: Validators.email,
          ),
          const SizedBox(height: 12),
          _PasswordField(controller: _password, validator: Validators.password),
          const SizedBox(height: 12),
          _PasswordField(
            controller: _confirm,
            label: 'Confirm password',
            onSubmit: _submit,
            validator: (v) => v == _password.text ? null : 'Passwords do not match.',
          ),
          const SizedBox(height: 16),
          GradientButton(
            onPressed: _submit,
            busy: _busy,
            label: 'Create account',
          ),
          const SizedBox(height: 8),
          Text(
            'This creates a citizen account only. Administrator and officer accounts cannot be '
            'self-registered.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------- first administrator

class _AdminSetupForm extends ConsumerStatefulWidget {
  const _AdminSetupForm({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  ConsumerState<_AdminSetupForm> createState() => _AdminSetupFormState();
}

class _AdminSetupFormState extends ConsumerState<_AdminSetupForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .createFirstAdmin(_name.text, _email.text, _password.text);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needs = ref.watch(needsSetupProvider);
    final scheme = Theme.of(context).colorScheme;
    return AuthScaffold(
      onBack: widget.onBack,
      compact: true,
      child: needs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(needsSetupProvider)),
        data: (open) => !open
            ? const EmptyState(
                icon: Icons.verified_user_outlined,
                message: 'An administrator already exists. Sign in with Administrator Login, or ask '
                    'them to create your account.')
            : Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Set up ${Brand.appName}',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                      'Create the first administrator. They manage departments, officers and '
                      'settings. This option disappears once an administrator exists.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                    validator: Validators.name,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 12),
                  _PasswordField(controller: _password, validator: Validators.password),
                  const SizedBox(height: 12),
                  _PasswordField(
                    controller: _confirm,
                    label: 'Confirm password',
                    onSubmit: _submit,
                    validator: (v) => v == _password.text ? null : 'Passwords do not match.',
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    onPressed: _submit,
                    busy: _busy,
                    label: 'Create administrator',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Accounts are stored on this phone. Keep these details safe: another '
                    'administrator can reset a password, but a lone administrator cannot.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
      ),
    );
  }
}
