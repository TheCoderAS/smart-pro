import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/failure.dart';

/// GET /api/audit rendered read-only. The exact body shape is
/// firmware-defined, so parsing is tolerant: a JSON array becomes
/// entries; a JSON object with a known list field is unwrapped; plain
/// text splits on newlines.
final auditProvider = FutureProvider<List<String>>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final res = await dio.get<dynamic>(Api.audit);
    return _parseAudit(res.data);
  } on DioException catch (e) {
    throw e.apiFailure;
  }
});

List<String> _parseAudit(dynamic data) {
  if (data == null) return const [];
  if (data is List) {
    return [for (final e in data) e.toString()];
  }
  if (data is Map<String, dynamic>) {
    for (final key in const ['audit', 'log', 'entries', 'lines']) {
      final inner = data[key];
      if (inner is List) return [for (final e in inner) e.toString()];
    }
    return [data.toString()];
  }
  return data
      .toString()
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
}

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
