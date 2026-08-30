import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/transport/ble_session.dart';
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/link_state.dart';
import '../../../core/transport/stay_alive.dart';
import '../../../core/transport/transport_coordinator.dart';
import '../../../core/transport/transport_manager.dart';
import '../../../core/widgets/transport_refusal.dart';
import '../../../core/ws/snapshot_cache.dart';
import '../../../core/ws/state_dto.dart';
import '../../../core/ws/state_socket.dart';
import '../../auth/application/session.dart';
import '../../onboarding/presentation/first_run_prompts.dart';
import '../../switches/presentation/rename_sheet.dart';
import '../application/master_cards.dart';
import '../application/switch_overrides.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Decide Wi-Fi vs BLE from the user's preference + reachability, then
    // ask the two once-only setup questions (story Epic 1 steps 4 and 5).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(transportCoordinatorProvider).reconcile();
      if (!mounted) return;
      // Bring the keep-ready service up once there is a session worth
      // holding open (Android only; a no-op elsewhere).
      await ref.read(stayAliveProvider).resume();
      if (!mounted) return;
      await runFirstRunPrompts(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(activeStateProvider);
    final status = ref.watch(socketStatusProvider);
    final transport = ref.watch(currentTransportProvider);

    // The dashboard can be on screen before the session has resolved —
    // the cached snapshot paints straight away — so the reconcile in
    // initState may have run while the token was still being restored.
    // Reconcile again the moment the session settles, or a
    // Bluetooth-preferring user stays on Wi-Fi for the rest of the app's
    // life: nothing else ever calls it.
    ref.listen(sessionProvider, (prev, next) {
      if (next.value is Authenticated && prev?.value is! Authenticated) {
        ref.read(transportCoordinatorProvider).reconcile();
      }
    });

    // Reconcile optimistic overrides against the authoritative snapshot
    // (API §4): confirmed ones clear, contradicted ones hold until the
    // firmware catches up — no flicker after "All off". Also record the
    // master (uid + name) so the BLE cold-start path can find it later
    // even if the user only ever signed in (never commissioned).
    ref.listen(activeStateProvider, (prev, next) {
      final snap = next.value;
      if (snap != null) {
        // A snapshot is proof the link works, on either transport — it
        // beats waiting for the next heartbeat tick.
        ref.read(linkStateProvider.notifier).markAlive();
        // Keep it, so the next cold start paints the house immediately
        // instead of a spinner.
        ref.read(snapshotCacheProvider.notifier).save(snap);
        ref.read(switchOverridesProvider.notifier).reconcile(snap.switches);
        ref.read(masterRegistryProvider.notifier).ensure(
              uid: snap.selfUid,
              name: snap.masterName,
            );
      }
    });

    // Live if we have it, else the last one we saw. The cached one paints
    // at once; LinkState keeps its controls disabled and its states
    // labelled "last seen" until the link is confirmed, so nothing here
    // can be acted on while it's stale.
    final snap = snapshot.value ?? ref.watch(snapshotCacheProvider);
    // An offline extension's switches leave the dashboard entirely (story
    // Epic 2) — they are not greyed out, they are gone, and they come back
    // on their own. The master decides presence; the app never infers it
    // from its own request failures. The extension list still shows the
    // board, marked offline with a last-seen time.
    final sections = snap == null
        ? const <MasterSection>[]
        : sectionsFrom(snap, ref.watch(masterCardOrderProvider));
    final switches = [for (final sec in sections) ...sec.switches];
    final hiddenOffline = snap == null
        ? 0
        : (snap.switches.length +
                snap.peers.fold<int>(0, (n, p) => n + p.switches.length)) -
            switches.length;

    // Over BLE, a failed scan/connect would otherwise spin forever —
    // surface it with a retry instead.
    final bleFailed = transport == TransportKind.ble &&
        ref.watch(bleSessionProvider).status == BleSessionStatus.failed;

    return Scaffold(
      body: RefreshIndicator(
        // Pull down to force the latest switch state now — re-request
        // over BLE, or reconnect the socket over Wi-Fi.
        onRefresh: () =>
            ref.read(transportCoordinatorProvider).refreshState(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          _DashboardHeader(
            snapshot: snap,
            status: status,
            transport: transport,
          ),
          if (snap == null && bleFailed)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _BleTrouble(),
            )
          else if (snapshot.isLoading && snap == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (switches.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else ...[
            SliverToBoxAdapter(child: _QuickTools(switches: switches)),
            // One master: a flat grid, because wrapping a single master's
            // switches in a collapsible card would just add a tap. A mesh:
            // one card per master, one open at a time (story Epic 7).
            if (sections.length <= 1)
              _SwitchGrid(
                switches: switches,
                // Always the master we're connected to when there is only
                // one section, so this is null — see MasterSection.relayUid.
                masterUid:
                    sections.isEmpty ? null : sections.first.relayUid,
              )
            else
              _MasterCards(sections: sections),
            if (hiddenOffline > 0)
              SliverToBoxAdapter(child: _OfflineNote(count: hiddenOffline)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
          ],
        ),
      ),
    );
  }
}

/// Branded hero header: master identity, live connection pill, and the
/// on/total summary. Collapses into a compact app bar on scroll.
class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader({
    required this.snapshot,
    required this.status,
    required this.transport,
  });

  final StateSnapshot? snapshot;
  final SocketStatus status;
  final TransportKind transport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final masterName = (snapshot?.masterName.isNotEmpty ?? false)
        ? snapshot!.masterName
        : l10n.appTitle;
    // In a mesh the app is set up with the whole home, so the home is
    // what the header names; the master actually answering is named on
    // its own card below. Standalone is unchanged — there is no mesh
    // name to show, and the master IS the home.
    final masters =
        ref.watch(masterRegistryProvider).value ?? const <SavedMaster>[];
    final home = masters.isEmpty ? null : masters.first;
    final meshName = (home?.inMesh ?? false) ? (home!.meshName ?? '') : '';
    final meshed = meshName.isNotEmpty;
    final name = meshed ? meshName : masterName;
    final switches = snapshot?.switches ?? const <SwitchState>[];
    final onCount = switches.where((s) => s.on).length;

    return SliverAppBar(
      pinned: true,
      expandedHeight: 140,
      // Match the app's 20px content gutter — the pill used to sit flush
      // against the left edge of the canvas.
      titleSpacing: 20,
      // The connection pill lives inline in the toolbar row (with the
      // quick-action icons) — one row, always visible.
      title: _StatusPill(status: status, transport: transport),
      actions: [
        IconButton(
          icon: const Icon(Icons.receipt_long_rounded),
          tooltip: 'Logs',
          onPressed: () => context.push(Routes.logs),
        ),
        IconButton(
          icon: const Icon(Icons.extension_rounded),
          tooltip: l10n.menuExtensions,
          onPressed: () => context.push(Routes.extensions),
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          tooltip: l10n.menuSettings,
          onPressed: () => context.push(Routes.settings),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.zero,
        background: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                UnisyncColors.accent.withValues(alpha: 0.18),
                scheme.surfaceContainerLowest.withValues(alpha: 0),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              // Below the toolbar row so the master name never rides
              // under the pill/icons.
              padding: const EdgeInsets.fromLTRB(20, kToolbarHeight, 20, 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      ),
                      if (snapshot?.peers.isNotEmpty ?? false)
                        _MeshBadge(peerCount: snapshot!.peers.length),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    switches.isEmpty
                        ? l10n.dashboardEmptyTitle
                        // Meshed: the header names the home, so the master
                        // actually answering is named here — it is still
                        // worth knowing which box you are talking to.
                        : meshed
                            ? '${l10n.onOfTotal(onCount, switches.length)}'
                                ' · $masterName'
                            : l10n.onOfTotal(onCount, switches.length),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final SocketStatus status;

  @override
  Widget build(BuildContext context) {
    final connected = status == SocketStatus.connected;
    final color = connected
        ? UnisyncColors.success
        : Theme.of(context).colorScheme.error;
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (connected) return dot;
    return dot.animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn().then().fade(
      duration: 700.ms,
      begin: 1,
      end: 0.3,
    );
  }
}

/// Live connection status as a soft pill — shows the transport
/// (Wi-Fi/Bluetooth) and, on tap, offers to switch. Public-feeling,
/// not an error.
class _StatusPill extends ConsumerWidget {
  const _StatusPill({required this.status, required this.transport});
  final SocketStatus status;
  final TransportKind transport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Over BLE, "connected" is the BLE session being connected; the WS
    // status only reflects the Wi-Fi path.
    final bleConnected =
        ref.watch(bleSessionProvider).status == BleSessionStatus.connected;
    final connected = transport == TransportKind.ble
        ? bleConnected
        : status == SocketStatus.connected;
    final label = connected ? l10n.connected : l10n.reconnecting;
    final color = connected ? UnisyncColors.success : scheme.error;
    final via = transport == TransportKind.ble
        ? l10n.viaBluetooth
        : l10n.viaWifi;
    final viaIcon = transport == TransportKind.ble
        ? Icons.bluetooth_rounded
        : Icons.wifi_rounded;

    return Semantics(
      liveRegion: !connected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _showTransportSheet(context, ref),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusDot(status: connected
                    ? SocketStatus.connected
                    : SocketStatus.connecting),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(viaIcon, size: 13, color: color),
                const SizedBox(width: 3),
                Text(
                  via,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTransportSheet(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final coordinator = ref.read(transportCoordinatorProvider);
    final current = ref.read(transportPreferenceProvider);
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.switchTransport,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            for (final entry in const [
              (TransportPreference.wifi, Icons.wifi_rounded),
              (TransportPreference.bluetooth, Icons.bluetooth_rounded),
            ])
              ListTile(
                leading: Icon(entry.$2),
                title: Text(_prefLabel(l10n, entry.$1)),
                subtitle: Text(_prefDesc(l10n, entry.$1)),
                trailing: current == entry.$1
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.of(sheetContext).pop();
                  final result = await coordinator.choose(entry.$1);
                  showTransportRefusal(messenger, l10n, result);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _prefLabel(AppLocalizations l10n, TransportPreference p) =>
    switch (p) {
      TransportPreference.wifi => l10n.transportWifi,
      TransportPreference.bluetooth => l10n.transportBluetooth,
    };

String _prefDesc(AppLocalizations l10n, TransportPreference p) => switch (p) {
  TransportPreference.wifi => l10n.transportWifiDesc,
  TransportPreference.bluetooth => l10n.transportBluetoothDesc,
};

class _MeshBadge extends StatelessWidget {
  const _MeshBadge({required this.peerCount});
  final int peerCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            l10n.meshBadge,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Handy quick tool — one-tap "All off". Fires the single kill-all
/// command (turns off every switch on every master in the mesh) rather
/// than looping per switch. Optimistic, like the tiles.
class _QuickTools extends ConsumerWidget {
  const _QuickTools({required this.switches});
  final List<SwitchState> switches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final linkUp = ref.watch(linkStateProvider).controlsEnabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: _QuickButton(
        icon: Icons.flash_off_rounded,
        label: l10n.allOff,
        // Same rule as the tiles: no acting on a link we can't confirm.
        onTap: linkUp ? () => _killAll(ref) : null,
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, curve: Curves.easeOut);
  }

  Future<void> _killAll(WidgetRef ref) async {
    final overrides = ref.read(switchOverridesProvider.notifier);
    // Optimistic: show every switch off immediately. One kill-all
    // command does the work — no per-switch loop.
    for (final sw in switches) {
      if (sw.online && sw.on) overrides.set(sw.id, false);
    }
    try {
      await ref.read(activeControlProvider).killAll();
    } on Exception {
      for (final sw in switches) {
        overrides.clear(sw.id);
      }
    }
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the BLE transport is active but the session failed to
/// find/connect to a master — offers a retry and a switch to Wi-Fi.
class _BleTrouble extends ConsumerWidget {
  const _BleTrouble();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled_rounded,
                size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(l10n.bleTroubleTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              // Prefer the session's own reason ("Sign in over Wi-Fi
              // first", "No switch found nearby…") over generic advice —
              // the accurate message was previously discarded.
              ref.watch(bleSessionProvider).error ?? l10n.bleTroubleBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(transportCoordinatorProvider).reconcile(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.tryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet footnote when switches have left the grid because their board is
/// unreachable. Without it the grid silently shrinks and reads as data loss.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? '1 switch is hidden while its extension is unreachable. '
                      'It comes back on its own.'
                  : '$count switches are hidden while their extensions are '
                      'unreachable. They come back on their own.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_to_home_screen_rounded,
                size: 44,
                color: scheme.primary,
              ),
            ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.dashboardEmptyTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.dashboardEmptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The flat single-master grid, with one long-press doing double duty:
/// drag a tile onto another to reorder, or lift without moving to
/// rename. Tap stays toggle-only. A separate reorder screen used to
/// carry this; the gesture everyone tries first now just works.
class _SwitchGrid extends ConsumerStatefulWidget {
  const _SwitchGrid({required this.switches, this.masterUid});

  final List<SwitchState> switches;
  final String? masterUid;

  @override
  ConsumerState<_SwitchGrid> createState() => _SwitchGridState();
}

class _SwitchGridState extends ConsumerState<_SwitchGrid> {
  /// The order the user last committed, painted immediately and kept
  /// until the master's snapshots confirm it (or the save fails).
  List<String>? _localOrder;

  /// The order shown *while a drag is in flight*: tiles step aside the
  /// moment the finger passes over them, so the grid always shows
  /// exactly what releasing would save. Null when nothing is dragging.
  List<String>? _previewOrder;
  String? _dragId;

  /// Moved less than this during the drag counts as "released in
  /// place" — which means rename, not reorder.
  static const _renameSlop = 16.0;

  List<SwitchState> get _display {
    final order = _previewOrder ?? _localOrder;
    if (order == null) return widget.switches;
    final byId = {for (final s in widget.switches) s.id: s};
    return [
      for (final id in order) ?byId.remove(id),
      // Anything the saved order doesn't know (a switch added since)
      // keeps its snapshot position at the end.
      ...byId.values,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final switches = _display;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 128,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final sw = switches[i];
            // Keyed at the top level so the live preview MOVES each
            // tile's element instead of recreating it — recreating the
            // dragged tile mid-gesture would kill the drag (its
            // onDragEnd dies with the state) and leave the grid stuck
            // in preview.
            return KeyedSubtree(
              key: ValueKey(sw.id),
              child: _DraggableSwitchTile(
                sw: sw,
                masterUid: widget.masterUid,
                renameSlop: _renameSlop,
                onDragStarted: _startDrag,
                onHover: _hover,
                onDragEnded: _endDrag,
              )
                  .animate()
                  .fadeIn(duration: 260.ms, delay: (40 * i).ms)
                  .slideY(begin: 0.15, curve: Curves.easeOut),
            );
          },
          childCount: switches.length,
          // The other half of the move-don't-recreate contract.
          findChildIndexCallback: (key) {
            final id = (key as ValueKey<String>).value;
            final index = switches.indexWhere((s) => s.id == id);
            return index < 0 ? null : index;
          },
        ),
      ),
    );
  }

  void _startDrag(String id) {
    setState(() {
      _dragId = id;
      _previewOrder = [for (final s in _display) s.id];
    });
  }

  /// Live reorder: the dragged tile takes [overId]'s slot the moment
  /// the finger reaches it, and everything between shifts one place.
  void _hover(String overId) {
    final drag = _dragId;
    final order = _previewOrder;
    if (drag == null || order == null || drag == overId) return;
    final from = order.indexOf(drag);
    final to = order.indexOf(overId);
    if (from < 0 || to < 0 || from == to) return;
    setState(() {
      final next = [...order]..removeAt(from);
      // Dragging forward lands after the hovered tile, backward lands
      // before it — the natural step-aside in both directions.
      next.insert(
        from < to ? next.indexOf(overId) + 1 : next.indexOf(overId),
        drag,
      );
      _previewOrder = next;
    });
  }

  /// Commit whatever the drag left on screen. Live preview means the
  /// visible grid IS the user's choice — a release anywhere keeps it.
  Future<void> _endDrag() async {
    final preview = _previewOrder;
    if (preview == null) return;
    final before = [for (final s in widget.switches) s.id];
    final changed = _localOrder != null
        ? !_sameOrder(preview, _localOrder!)
        : !_sameOrder(preview, before);
    setState(() {
      _dragId = null;
      _previewOrder = null;
      if (changed) _localOrder = preview;
    });
    if (!changed) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(activeControlProvider).reorder(preview);
      // Nudge a fresh snapshot so the master's order catches up without
      // waiting on the next spontaneous push.
      await ref.read(transportCoordinatorProvider).refreshState();
    } on Exception {
      if (mounted) setState(() => _localOrder = null);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save the order — check the connection.'),
        ),
      );
    }
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One grid cell: a [SwitchTile] that can be long-press-dragged (the
/// grid re-arranges live under the finger) or long-pressed and released
/// in place (rename).
class _DraggableSwitchTile extends ConsumerStatefulWidget {
  const _DraggableSwitchTile({
    required this.sw,
    required this.masterUid,
    required this.renameSlop,
    required this.onDragStarted,
    required this.onHover,
    required this.onDragEnded,
  });

  final SwitchState sw;
  final String? masterUid;
  final double renameSlop;
  final void Function(String id) onDragStarted;
  final void Function(String overId) onHover;
  final VoidCallback onDragEnded;

  @override
  ConsumerState<_DraggableSwitchTile> createState() =>
      _DraggableSwitchTileState();
}

class _DraggableSwitchTileState extends ConsumerState<_DraggableSwitchTile> {
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    // The grid's own long-press owns the gesture here, so the tile's
    // built-in rename long-press is off (handleLongPress: false).
    final tile = SwitchTile(
      sw: widget.sw,
      masterUid: widget.masterUid,
      handleLongPress: false,
    );
    return LayoutBuilder(
      builder: (context, constraints) => LongPressDraggable<String>(
        data: widget.sw.id,
        // Haptic long-press pickup, sized exactly like the resting tile.
        feedback: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.9, child: tile),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: tile),
        onDragStarted: () {
          _dragDistance = 0;
          widget.onDragStarted(widget.sw.id);
        },
        onDragUpdate: (d) => _dragDistance += d.delta.distance,
        onDragEnd: (details) {
          // The grid commits whatever the live preview shows; a pickup
          // that never really moved is the rename gesture instead.
          widget.onDragEnded();
          if (!details.wasAccepted && _dragDistance < widget.renameSlop) {
            showRenameSwitchSheet(context, ref, widget.sw);
          }
        },
        child: DragTarget<String>(
          // Entering a sibling's cell re-arranges the grid right away —
          // this hover IS the reorder; the drop just ends it.
          onWillAcceptWithDetails: (d) {
            if (d.data == widget.sw.id) return false;
            widget.onHover(widget.sw.id);
            return true;
          },
          onAcceptWithDetails: (_) {},
          builder: (context, candidates, _) => tile,
        ),
      ),
    );
  }
}

/// One collapsible card per master, one open at a time. A master that has
/// gone quiet keeps its card — with its switches disabled and a last-seen
/// time — rather than disappearing, so the user sees the state before
/// acting rather than discovering it through a failed tap.
class _MasterCards extends ConsumerWidget {
  const _MasterCards({required this.sections});

  final List<MasterSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(expandedMasterProvider);
    // Arriving on a mesh dashboard with everything shut would read as
    // empty, so the first card opens itself.
    if (expanded == null && sections.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(expandedMasterProvider.notifier).defaultTo(sections.first.uid);
      });
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.builder(
        itemCount: sections.length,
        itemBuilder: (context, i) => _MasterCard(
          section: sections[i],
          open: sections[i].uid == expanded,
        ),
      ),
    );
  }
}

class _MasterCard extends ConsumerWidget {
  const _MasterCard({required this.section, required this.open});

  final MasterSection section;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final on = section.switches.where((s) => s.on).length;
    final subtitle = section.online
        ? '$on of ${section.switches.length} on'
        : '${section.presence.label} · last seen '
            '${lastSeenLabel(section.lastSeen)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              section.isSelf ? Icons.router : Icons.router_outlined,
              color: section.online ? scheme.primary : scheme.onSurfaceVariant,
            ),
            title: Text(section.name),
            subtitle: Text(subtitle),
            trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
            onTap: () =>
                ref.read(expandedMasterProvider.notifier).toggle(section.uid),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState:
                open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: section.switches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No switches reachable right now.'),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisExtent: 128,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: section.switches.length,
                      itemBuilder: (context, i) => SwitchTile(
                        sw: section.switches[i],
                        // Self is driven directly; a peer is relayed.
                        masterUid: section.relayUid,
                        enabled: section.online,
                      ),
                    ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// One relay. Renders the optimistic override when present, else the
/// snapshot state. Animated accent glow + press feedback when on.
/// Public for widget tests.
class SwitchTile extends ConsumerStatefulWidget {
  const SwitchTile({
    required this.sw,
    this.masterUid,
    this.enabled = true,
    this.handleLongPress = true,
    super.key,
  });

  final SwitchState sw;

  /// The master that owns this switch, when it isn't the one the app is
  /// connected to. Null drives a local relay.
  final String? masterUid;

  /// False when the owning master itself is unreachable.
  final bool enabled;

  /// False when a parent (the draggable home grid) owns the long-press
  /// gesture — two long-press handlers on one tile would fight.
  final bool handleLongPress;

  @override
  ConsumerState<SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends ConsumerState<SwitchTile> {
  bool _pressed = false;

  SwitchState get sw => widget.sw;

  @override
  Widget build(BuildContext context) {
    final overrides = ref.watch(switchOverridesProvider);
    final on = overrides[sw.id] ?? sw.on;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // Two separate reasons a tile can't be driven, and they read
    // differently to the user: the board is offline, or *we* are. When the
    // link is down the states on screen are last-seen values, not truth, so
    // the story says controls disable rather than letting someone find out
    // by tapping (Epic 1, connection awareness).
    final linkUp = ref.watch(linkStateProvider).controlsEnabled;
    final online = sw.online && widget.enabled;
    final live = online && linkUp;
    final stateLabel = !online
        ? l10n.switchOffline
        : !linkUp
            ? '${on ? l10n.switchOn : l10n.switchOff} · last seen'
            : (on ? l10n.switchOn : l10n.switchOff);

    final accent = UnisyncColors.accent;

    return Semantics(
      label: '${sw.name.isEmpty ? sw.id : sw.name}, $stateLabel',
      button: live,
      toggled: on,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: on
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.06),
                    ],
                  )
                : null,
            color: on ? null : scheme.surface,
            border: Border.all(
              color: on
                  ? accent.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
              width: on ? 1.4 : 1,
            ),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 18,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: live ? () => _toggle(on) : null,
            // Rename works on either transport (firmware v11.18.0).
            onLongPress: widget.handleLongPress
                ? () => showRenameSwitchSheet(context, ref, sw)
                : null,
            onTapDown: live ? (_) => setState(() => _pressed = true) : null,
            onTapUp: live ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: () => setState(() => _pressed = false),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _PowerGlyph(on: on, online: online),
                      const Spacer(),
                      if (!online)
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 18,
                          color: scheme.error,
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    sw.name.isEmpty ? sw.id : sw.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  ExcludeSemantics(
                    child: Text(
                      stateLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: on
                            ? accent
                            : scheme.onSurfaceVariant,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(bool currentlyOn) async {
    setState(() => _pressed = false);
    final next = !currentlyOn;
    final overrides = ref.read(switchOverridesProvider.notifier);
    overrides.set(sw.id, next);
    try {
      await ref.read(activeControlProvider).setRelay(
            id: sw.id,
            on: next,
            ch: sw.ch,
            masterUid: widget.masterUid,
          );
      // Leave the override in place; the next snapshot clears it.
    } on Exception {
      // Command failed — snap back to the snapshot state.
      overrides.clear(sw.id);
    }
  }
}

/// Circular power indicator that fills with the accent when on.
class _PowerGlyph extends StatelessWidget {
  const _PowerGlyph({required this.on, required this.online});
  final bool on;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = UnisyncColors.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? accent : scheme.surfaceContainerHighest,
        border: Border.all(
          color: on ? accent : scheme.outlineVariant,
        ),
      ),
      child: Icon(
        Icons.power_settings_new_rounded,
        size: 20,
        color: on
            ? Colors.white
            : (online ? scheme.onSurfaceVariant : scheme.outline),
      ),
    );
  }
}
