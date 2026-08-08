import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/transport/transport_manager.dart';

/// The activity log, read-only, over whichever transport is active —
/// `GET /api/audit` on Wi-Fi or the `audit` command over BLE (spec v2).
/// Parsing is tolerant and lives in the transport layer.
final auditProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(activeControlProvider).audit();
});

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audit = ref.watch(auditProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(auditProvider.future),
        child: switch (audit) {
          AsyncValue(value: final List<String> lines) when lines.isNotEmpty =>
            ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: lines.length,
              separatorBuilder: (context, i) => const Divider(height: 1),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  lines[i],
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          AsyncValue(value: final List<String> _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.all(48),
                  child: Text('The log is empty.', textAlign: TextAlign.center),
                ),
              ],
            ),
          AsyncValue(:final Object error) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Text(
                    error is ApiFailure
                        ? error.describe()
                        : 'Could not load the log.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}
