import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../widgets/thematic_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const routePath = '/login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          // Background Gradient blobs
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: cs.secondary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                final content = ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: isWide
                        ? Row(
                            children: [
                              Expanded(child: _MarketingPanel(cs: cs)),
                              const SizedBox(width: 48),
                              const SizedBox(width: 400, child: _SignInCard()),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                const SizedBox(height: 48),
                                _LoginHeader(cs: cs),
                                const SizedBox(height: 48),
                                const _SignInCard(),
                              ],
                            ),
                          ),
                  ),
                );

                return Center(child: content);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(Icons.bolt, size: 48, color: cs.primary),
        ),
        const SizedBox(height: 24),
        Text(
          'MikroTap',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            color: cs.onSurface,
          ),
        ),
        Text(
          'Hotspot Management Redefined',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
        ),
      ],
    );
  }
}

class _SignInCard extends ConsumerStatefulWidget {
  const _SignInCard();

  @override
  ConsumerState<_SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends ConsumerState<_SignInCard> {
  bool _loading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final cs = Theme.of(context).colorScheme;

    return ProCard(
      padding: const EdgeInsets.all(32),
      children: [
        const Text(
          'Welcome Back',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Secure authentication via Google',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        ),
        const SizedBox(height: 32),
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.error.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: cs.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        FilledButton(
          onPressed: (_loading || auth.isLoading)
              ? null
              : () async {
                  setState(() {
                    _loading = true;
                    _errorMessage = null;
                  });
                  try {
                    await ref.read(authRepositoryProvider).signInWithGoogle();
                  } catch (e) {
                    if (mounted) {
                      setState(
                        () => _errorMessage = e.toString().replaceFirst(
                          'Exception: ',
                          '',
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.login_rounded, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'Continue with Google',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),
        Text(
          'By continuing, you agree to our Terms of Service and Privacy Policy.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
        ),
      ],
    );
  }
}

class _MarketingPanel extends StatelessWidget {
  const _MarketingPanel({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.rocket_launch_rounded, color: cs.primary),
        ),
        const SizedBox(height: 32),
        Text(
          'Ultimate Hotspot\nControl.',
          style: TextStyle(
            fontSize: 48,
            height: 1.1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.5,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Automate your MikroTik infrastructure with our zero-touch provisioning platform.',
          style: TextStyle(
            fontSize: 18,
            color: cs.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 48),
        _FeatureItem(
          cs: cs,
          icon: Icons.bolt,
          title: 'Zero-touch setup',
          subtitle: 'Provision routers in under 2 minutes',
        ),
        const SizedBox(height: 24),
        _FeatureItem(
          cs: cs,
          icon: Icons.qr_code_2,
          title: 'Smart Vouchers',
          subtitle: 'QR codes, PDFs and thermal printing ready',
        ),
        const SizedBox(height: 24),
        _FeatureItem(
          cs: cs,
          icon: Icons.analytics_outlined,
          title: 'Real-time Analytics',
          subtitle: 'Monitor revenue and bandwidth live',
        ),
      ],
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.cs,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final ColorScheme cs;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: cs.primary, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
