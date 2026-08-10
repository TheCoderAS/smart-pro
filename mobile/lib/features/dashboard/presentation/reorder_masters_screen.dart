import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/transport/transport_manager.dart';
import '../application/master_cards.dart';

/// Drag-to-reorder the master cards on the dashboard.
///
/// This one order deliberately does *not* go to the master and does not
/// sync between people: different members of a household want their own
/// nearest master on top. Switch order inside a master is the opposite —
/// that lives on the master so everyone sees the same thing.
class ReorderMastersScreen extends ConsumerStatefulWidget {
  const ReorderMastersScreen({super.key});

  @override
  ConsumerState<ReorderMastersScreen> createState() =>
      _ReorderMastersScreenState();
}

class _ReorderMastersScreenState extends ConsumerState<ReorderMastersScreen> {
  List<MasterSection>? _working;

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(activeStateProvider).value;
    final sections = _working ??
        (snap == null
            ? const <MasterSection>[]
            : sectionsFrom(snap, ref.watch(masterCardOrderProvider)));
    final dirty = _working != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder masters'),
        actions: [
          TextButton(
            onPressed: dirty ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: sections.length < 2
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'There is only one master here, so there is nothing to '
                  'reorder yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'This order is yours alone — it stays on this phone and '
                    'nobody else in the house sees it.',
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: sections.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final list = [...sections];
                        final item = list.removeAt(oldIndex);
                        list.insert(newIndex, item);
                        _working = list;
                      });
                    },
                    itemBuilder: (context, i) {
                      final s = sections[i];
                      return ListTile(
                        key: ValueKey(s.uid),
                        leading: const Icon(Icons.drag_handle),
                        title: Text(s.name),
                        subtitle: Text(
                          s.isSelf
                              ? 'The master you are connected to'
                              : '${s.switches.length} switches',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    final order = [for (final s in _working ?? const <MasterSection>[]) s.uid];
    await ref.read(masterCardOrderProvider.notifier).set(order);
    if (mounted) Navigator.of(context).pop();
  }
}
