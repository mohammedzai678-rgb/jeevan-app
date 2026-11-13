import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/jeevan_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _signUp = false;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _googleSignIn() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(authProvider).signInWithGoogle();
    } on AuthException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Google sign-in failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    if (_signUp && name.isEmpty) {
      showSnack(context, 'Please enter your full name.', error: true);
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      showSnack(context, 'Please enter a valid email address.', error: true);
      return;
    }
    if (pass.length < 6) {
      showSnack(context, 'Password must be at least 6 characters.', error: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final auth = ref.read(authProvider);
      if (_signUp) {
        final signedIn = await auth.signUp(email, pass, name);
        if (!signedIn && mounted) {
          showSnack(context, 'Account created! Please check your email to confirm, then sign in.');
          setState(() => _signUp = false);
        }
      } else {
        await auth.signIn(email, pass);
      }
    } on AuthException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not connect: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  
  Future<void> _openForgotPasswordDialog() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    bool sending = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Palette.outline),
          ),
          title: const Text('Reset Password', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter your registered email address to receive password recovery instructions.', style: TextStyle(color: Palette.textDim, fontSize: 13)),
              const SizedBox(height: 14),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: sending ? null : () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: sending ? null : () async {
                final email = emailCtrl.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  showSnack(ctx, 'Please enter a valid email address.', error: true);
                  return;
                }
                setDialogState(() => sending = true);
                try {
                  await ref.read(authProvider).recoverPassword(email);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) showSnack(context, 'Password reset link sent to $email!');
                } catch (e) {
                  if (ctx.mounted) showSnack(ctx, 'Error: $e', error: true);
                } finally {
                  if (ctx.mounted) setDialogState(() => sending = false);
                }
              },
              child: sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Send Reset Link'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openServerDialog() async {
    final store = ref.read(storeProvider);
    final ctrl = TextEditingController(text: store.serverUrlOverride ?? Config.apiBaseUrl);
    String? pingStatus;
    bool pingError = false;
    bool pinging = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Palette.outline),
          ),
          title: const Text(
            'Server URL',
            style: TextStyle(color: Palette.text, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configure the FastAPI gateway URL for live vitals, SOS dispatch, and RAG streaming.',
                style: TextStyle(color: Palette.textDim, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: const TextStyle(color: Palette.text, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'FastAPI Base URL',
                  hintText: 'http://192.168.1.20:8000',
                  prefixIcon: Icon(Icons.dns_rounded, color: Palette.teal),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: pinging
                        ? null
                        : () async {
                            setDialogState(() {
                              pinging = true;
                              pingStatus = null;
                            });
                            await store.setServerUrl(ctrl.text.trim());
                            try {
                              final ms = await ref.read(apiProvider).pingMs();
                              setDialogState(() {
                                pinging = false;
                                pingError = false;
                                pingStatus = 'Online • $ms ms RTT';
                              });
                            } catch (e) {
                              setDialogState(() {
                                pinging = false;
                                pingError = true;
                                pingStatus = 'Unreachable';
                              });
                            }
                          },
                    icon: pinging
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Palette.teal),
                          )
                        : const Icon(Icons.bolt_rounded, size: 18, color: Palette.teal),
                    label: const Text('Test Ping'),
                  ),
                  const SizedBox(width: 10),
                  if (pingStatus != null)
                    Expanded(
                      child: Text(
                        pingStatus!,
                        style: TextStyle(
                          color: pingError ? Palette.red : Palette.green,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await store.setServerUrl(null);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) showSnack(context, 'Reset to default server URL.');
              },
              child: const Text('Reset Default', style: TextStyle(color: Palette.textDim)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 42)),
              onPressed: () async {
                await store.setServerUrl(ctrl.text.trim());
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) showSnack(context, 'Server URL saved.');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: Stack(
        children: [
          // Subtle crimson glow at the top.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.85),
                  radius: 0.95,
                  colors: [
                    Palette.red.withValues(alpha: 0.14),
                    Palette.red.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: Gap.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const JeevanLogo(size: 92),
                      const SizedBox(height: Gap.lg),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            height: 1.1,
                          ),
                          children: [
                            const TextSpan(text: 'Jeevan', style: TextStyle(color: Palette.text)),
                            const TextSpan(text: 'Care', style: TextStyle(color: Palette.red)),
                          ],
                        ),
                      ),
                      const SizedBox(height: Gap.sm),
                      const Text(
                        'Your health, always within reach.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Palette.textDim,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: Gap.xl),
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Palette.surfaceHi,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _ModeTab(
                                      label: 'Sign in',
                                      selected: !_signUp,
                                      onTap: () => setState(() => _signUp = false),
                                    ),
                                  ),
                                  Expanded(
                                    child: _ModeTab(
                                      label: 'Create account',
                                      selected: _signUp,
                                      onTap: () => setState(() => _signUp = true),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: Gap.lg),
                            if (_signUp) ...[
                              TextField(
                                controller: _nameCtrl,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(color: Palette.text),
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  prefixIcon: Icon(Icons.person_outline_rounded, color: Palette.textDim),
                                ),
                              ),
                              const SizedBox(height: Gap.md),
                            ],
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(color: Palette.text),
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.mail_outline_rounded, color: Palette.textDim),
                              ),
                            ),
                            const SizedBox(height: Gap.md),
                            TextField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              style: const TextStyle(color: Palette.text),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, color: Palette.textDim),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: Palette.textDim,
                                  ),
                                  tooltip: _obscure ? 'Show password' : 'Hide password',
                                ),
                              ),
                            ),
                            if (!_signUp) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: Palette.red,
                                  ),
                                  onPressed: _openForgotPasswordDialog,
                                  child: const Text('Forgot password?', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                            const SizedBox(height: Gap.md),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                    )
                                  : Text(_signUp ? 'Create account' : 'Sign in'),
                            ),
                            const SizedBox(height: Gap.xs),

                            // ── Divider ──
                            Row(
                              children: [
                                const Expanded(child: Divider(color: Palette.outline)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('or', style: TextStyle(color: Palette.textDim, fontSize: 12.5)),
                                ),
                                const Expanded(child: Divider(color: Palette.outline)),
                              ],
                            ),
                            const SizedBox(height: Gap.xs),

                            // ── Google Sign-In ──
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                side: const BorderSide(color: Palette.outline),
                                foregroundColor: Palette.text,
                              ),
                              onPressed: _busy ? null : _googleSignIn,
                              icon: const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF4285F4))),
                              label: const Text('Continue with Google'),
                            ),

                          ],
                        ),
                      ),
                      const SizedBox(height: Gap.sm),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Palette.textMuted),
                        onPressed: _openServerDialog,
                        icon: const Icon(Icons.settings_ethernet_rounded, size: 16),
                        label: const Text('Server settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Palette.redLight : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Palette.red : Palette.textDim,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
// Jeevan sync: 2026-11-13
