import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/log_buffer.dart';

/// What the app has been doing, readable on the phone.
///
/// Exists because diagnosing anything on real hardware otherwise means
/// tethering to a laptop for `adb logcat` — which is friction on every
/// round of bench testing, and no help at all when the phone is the only
/// thing to hand. Newest at the bottom, like a console, with a copy button
/// so a report can be pasted straight into a message.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: logBuffer.asText()));
              messenger.showSnackBar(
                const SnackBar(content: Text('Logs copied')),
              );
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => logBuffer.clear(),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: logBuffer.revision,
        builder: (context, _, _) {
          final lines = logBuffer.lines;
          if (lines.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing logged yet. Use the app for a moment and come '
                  'back — this fills up as things happen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          // Anchored to the bottom so the newest line is the one in view,
          // which is what anyone opening this is looking for.
          WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
          return Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: lines.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(
                  lines[i],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
