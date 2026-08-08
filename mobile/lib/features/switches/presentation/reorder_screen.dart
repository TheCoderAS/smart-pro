import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/transport/transport_manager.dart';
import '../../../core/ws/state_dto.dart';

/// Drag-to-reorder. Local order is kept while dragging; "Save" commits
/// the id order via POST /api/switch/reorder and the next snapshot
/// becomes the source of truth again.
class ReorderScreen extends ConsumerStatefulWidget {
  const ReorderScreen({super.key});

  @override
  ConsumerState<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends ConsumerState<ReorderScreen> {
  List<SwitchState>? _working;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(activeStateProvider).value;
    final switches = _working ?? snapshot?.switches ?? const <SwitchState>[];
    final dirty = _working != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder switches'),
        actions: [
          TextButton(
            onPressed: dirty ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: switches.isEmpty
          ? const Center(child: Text('No switches to reorder.'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: switches.length,
              // onReorderItem (Flutter 3.42+) delivers newIndex already
              // adjusted for the removed item — no manual fix-up.
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final list = [...switches];
                  final item = list.removeAt(oldIndex);
                  list.insert(newIndex, item);
                  _working = list;
                });
              },
              itemBuilder: (context, i) {
                final sw = switches[i];
                return ListTile(
                  key: ValueKey(sw.id),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(sw.name.isEmpty ? sw.id : sw.name),
                  subtitle: Text(sw.id),
                );
              },
            ),
    );
  }

  Future<void> _save() async {
    final order = _working;
    if (order == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(activeControlProvider)
          .reorder([for (final sw in order) sw.id]);
      navigator.pop();
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save the order — check the connection.'),
        ),
      );
    }
  }
}
