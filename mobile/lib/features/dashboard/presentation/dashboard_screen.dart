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
import '../../../core/widgets/wifi_guard.dart';
import '../../../core/ws/state_dto.dart';
import '../../../core/ws/state_socket.dart';
import '../../onboarding/presentation/first_run_prompts.dart';
import '../../settings/presentation/master_switcher.dart';
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
    // The notification is a status line, so it has to follow the link.
    ref.listen(linkStateProvider, (_, _) {
      ref.read(stayAliveProvider).refresh();
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
        ref.read(switchOverridesProvider.notifier).reconcile(snap.switches);
        ref.read(masterRegistryProvider.notifier).ensure(
              uid: snap.selfUid,
              name: snap.masterName,
            );
      }
    });

    final snap = snapshot.value;
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
    final name = (snapshot?.masterName.isNotEmpty ?? false)
        ? snapshot!.masterName
        : l10n.appTitle;
    final switches = snapshot?.switches ?? const <SwitchState>[];
    final onCount = switches.where((s) => s.on).length;

    return SliverAppBar(
      pinned: true,
      expandedHeight: 178,
      titleSpacing: 0,
      // The connection pill lives inline in the toolbar row (with the
      // grid, reconnect and menu icons) — one row, always visible.
      leading: IconButton(
        tooltip: l10n.yourSwitches,
        icon: const Icon(Icons.grid_view_rounded),
        onPressed: () => showMasterSwitcher(context, ref),
      ),
      title: _StatusPill(status: status, transport: transport),
      actions: [
        _OverflowMenu(),
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
              padding: const EdgeInsets.fromLTRB(20, kToolbarHeight + 8, 20, 16),
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
              (TransportPreference.auto, Icons.autorenew_rounded),
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
      TransportPreference.auto => l10n.transportAuto,
      TransportPreference.wifi => l10n.transportWifi,
      TransportPreference.bluetooth => l10n.transportBluetooth,
    };

String _prefDesc(AppLocalizations l10n, TransportPreference p) => switch (p) {
  TransportPreference.auto => l10n.transportAutoDesc,
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

class _OverflowMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (v) async {
        // Reorder, extensions, activity log and firmware *info* all work
        // over Bluetooth (BLE spec v2). Only mesh admin stays Wi-Fi-only
        // here; firmware *transfer* is guarded inside its own screen.
        switch (v) {
          case 'reorder':
            unawaited(context.push(Routes.reorder));
          case 'reorderMasters':
            unawaited(context.push(Routes.reorderMasters));
          case 'extensions':
            unawaited(context.push(Routes.extensions));
          case 'mesh':
            if (requireWifi(context, ref)) unawaited(context.push(Routes.mesh));
          case 'firmware':
            unawaited(context.push(Routes.firmware));
          case 'settings':
            unawaited(context.push(Routes.settings));
        }
      },
      itemBuilder: (context) => [
        _menuItem('extensions', Icons.extension_rounded, l10n.menuExtensions),
        _menuItem('mesh', Icons.hub_rounded, l10n.menuMesh),
        _menuItem('firmware', Icons.system_update_rounded, l10n.menuFirmware),
        _menuItem('reorder', Icons.swap_vert_rounded, l10n.menuReorder),
        // Only worth offering once there is more than one master card.
        if (_hasSeveralMasters(ref))
          _menuItem('reorderMasters', Icons.reorder_rounded, 'Reorder masters'),
        _menuItem('settings', Icons.settings_rounded, l10n.menuSettings),
      ],
    );
  }

  bool _hasSeveralMasters(WidgetRef ref) =>
      (ref.read(activeStateProvider).value?.peers.length ?? 0) > 0;

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
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

class _SwitchGrid extends StatelessWidget {
  const _SwitchGrid({required this.switches, this.masterUid});

  final List<SwitchState> switches;
  final String? masterUid;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 128,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          return SwitchTile(sw: switches[i], masterUid: masterUid)
              .animate()
              .fadeIn(duration: 260.ms, delay: (40 * i).ms)
              .slideY(begin: 0.15, curve: Curves.easeOut);
        }, childCount: switches.length),
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
    super.key,
  });

  final SwitchState sw;

  /// The master that owns this switch, when it isn't the one the app is
  /// connected to. Null drives a local relay.
  final String? masterUid;

  /// False when the owning master itself is unreachable.
  final bool enabled;

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
            onLongPress: () => showRenameSwitchSheet(context, ref, sw),
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
