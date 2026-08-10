import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session.dart';
import '../application/first_run.dart';

/// What a fresh install opens on (story Epic 1): product branding and one
/// clear way into setup.
///
/// Not an empty dashboard, and not a bare login form — before the welcome
/// screen existed, a first launch with no master nearby dropped the user
/// straight onto "can't reach your switch", which reads as a broken product
/// rather than a product not set up yet.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Future<void> start() async {
      await ref.read(firstRunProvider.notifier).markWelcomeSeen();
      await ref.read(sessionProvider.notifier).refresh();
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary,
                      scheme.primary.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lightbulb_rounded,
                  size: 56,
                  color: scheme.onPrimary,
                ),
              ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 28),
              Text(
                'Unisync',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
              const SizedBox(height: 10),
              Text(
                'Your switches, your network, your home.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ).animate().fadeIn(delay: 250.ms, duration: 400.ms),
              const Spacer(),
              const _SetupStep(
                index: 1,
                icon: Icons.power_settings_new_rounded,
                title: 'Power on your switch',
                body: 'It starts broadcasting its own Wi-Fi network.',
              ),
              const _SetupStep(
                index: 2,
                icon: Icons.wifi_rounded,
                title: 'Join that network',
                body: 'The network name and password are on the card in the '
                    'box. Your phone keeps its mobile data.',
              ),
              const _SetupStep(
                index: 3,
                icon: Icons.check_circle_outline_rounded,
                title: 'Come back here',
                body: 'The same password signs you in. No account, no '
                    'internet, no Bluetooth needed.',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: start,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Set up my switch'),
                ),
              ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
              const SizedBox(height: 8),
              TextButton(
                onPressed: start,
                child: const Text("I've already joined the network"),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(
          delay: Duration(milliseconds: 250 + index * 80),
          duration: 400.ms,
        );
  }
}
