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
import '../../../core/transport/transport_coordinator.dart';
import '../../../core/transport/transport_manager.dart';
import '../../../core/ws/state_dto.dart';
import '../../../core/ws/state_socket.dart';
import '../../settings/presentation/master_switcher.dart';
import '../../switches/presentation/rename_sheet.dart';
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
    // Decide Wi-Fi vs BLE from the user's preference + reachability.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transportCoordinatorProvider).reconcile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(activeStateProvider);
    final status = ref.watch(socketStatusProvider);
    final transport = ref.watch(currentTransportProvider);

    // Every snapshot is authoritative (API §4) — clear optimistic
    // overrides the moment one lands, confirmed or contradicted. Also
    // record the master (uid + name) so the BLE cold-start path can find
    // it later even if the user only ever signed in (never commissioned).
    ref.listen(activeStateProvider, (prev, next) {
      final snap = next.value;
      if (snap != null) {
        ref.read(switchOverridesProvider.notifier).clearAll();
        ref.read(masterRegistryProvider.notifier).ensure(
              uid: snap.selfUid,
              name: snap.masterName,
            );
      }
    });

    final snap = snapshot.value;
    final switches = snap?.switches ?? const <SwitchState>[];

    // Over BLE, a failed scan/connect would otherwise spin forever —
    // surface it with a retry instead.
    final bleFailed = transport == TransportKind.ble &&
        ref.watch(bleSessionProvider).status == BleSessionStatus.failed;

    return Scaffold(
      body: CustomScrollView(
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
            _SwitchGrid(switches: switches),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
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
      expandedHeight: 200,
      leading: IconButton(
        tooltip: l10n.yourSwitches,
        icon: const Icon(Icons.grid_view_rounded),
        onPressed: () => showMasterSwitcher(context, ref),
      ),
      actions: [
        IconButton(
          tooltip: l10n.reconnect,
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.read(transportCoordinatorProvider).reconcile(),
        ),
        _OverflowMenu(),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(
          start: 56,
          bottom: 16,
          end: 16,
        ),
        title: _CollapsedTitle(name: name, status: status),
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
              // Top clears the pinned toolbar (leading/actions) so the
              // status pill never sits under the grid/menu icons; bottom
              // keeps the title off the content below.
              padding: const EdgeInsets.fromLTRB(20, kToolbarHeight + 4, 20, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusPill(status: status, transport: transport),
                  const SizedBox(height: 12),
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

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.name, required this.status});

  final String name;
  final SocketStatus status;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final t = settings == null
        ? 0.0
        : ((settings.maxExtent - settings.currentExtent) /
                  (settings.maxExtent - settings.minExtent))
              .clamp(0.0, 1.0);
    // Only show the compact title once mostly collapsed, so it doesn't
    // fight the big header title.
    return Opacity(
      opacity: t > 0.7 ? (t - 0.7) / 0.3 : 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(status: status),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
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
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  coordinator.choose(entry.$1);
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

/// Returns true when the active transport can carry a setup/maintenance
/// action (Wi-Fi). Over BLE, shows a sheet steering the user to Wi-Fi
/// and returns false.
bool _guardWifi(BuildContext context, WidgetRef ref) {
  if (ref.read(currentTransportProvider) != TransportKind.ble) return true;
  _showWifiNeeded(context, ref);
  return false;
}

void _showWifiNeeded(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.wifiOnlyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.wifiOnlyBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  ref
                      .read(transportCoordinatorProvider)
                      .choose(TransportPreference.wifi);
                },
                icon: const Icon(Icons.wifi_rounded),
                label: Text(l10n.joinWifi),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

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
        // Setup/maintenance flows aren't available over Bluetooth (BLE
        // spec §Not supported) — steer to Wi-Fi instead of a dead end.
        switch (v) {
          case 'reorder':
            if (_guardWifi(context, ref)) unawaited(context.push(Routes.reorder));
          case 'extensions':
            if (_guardWifi(context, ref)) {
              unawaited(context.push(Routes.extensions));
            }
          case 'mesh':
            if (_guardWifi(context, ref)) unawaited(context.push(Routes.mesh));
          case 'firmware':
            if (_guardWifi(context, ref)) {
              unawaited(context.push(Routes.firmware));
            }
          case 'audit':
            if (_guardWifi(context, ref)) unawaited(context.push(Routes.audit));
          case 'settings':
            unawaited(context.push(Routes.settings));
        }
      },
      itemBuilder: (context) => [
        _menuItem('extensions', Icons.extension_rounded, l10n.menuExtensions),
        _menuItem('mesh', Icons.hub_rounded, l10n.menuMesh),
        _menuItem('firmware', Icons.system_update_rounded, l10n.menuFirmware),
        _menuItem('reorder', Icons.swap_vert_rounded, l10n.menuReorder),
        _menuItem('audit', Icons.receipt_long_rounded, l10n.menuAudit),
        _menuItem('settings', Icons.settings_rounded, l10n.menuSettings),
      ],
    );
  }

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

/// Handy quick tools — one-tap All on / All off across every online
/// switch. Optimistic, like the tiles.
class _QuickTools extends ConsumerWidget {
  const _QuickTools({required this.switches});
  final List<SwitchState> switches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: _QuickButton(
              icon: Icons.flash_on_rounded,
              label: l10n.allOn,
              onTap: () => _setAll(ref, true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickButton(
              icon: Icons.flash_off_rounded,
              label: l10n.allOff,
              onTap: () => _confirmAllOff(context, ref),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, curve: Curves.easeOut);
  }

  Future<void> _setAll(WidgetRef ref, bool on) async {
    final overrides = ref.read(switchOverridesProvider.notifier);
    final repo = ref.read(activeControlProvider);
    for (final sw in switches) {
      if (!sw.online || sw.on == on) continue;
      overrides.set(sw.id, on);
      try {
        await repo.setRelay(id: sw.id, on: on, ch: sw.ch);
      } on Exception {
        overrides.clear(sw.id);
      }
    }
  }

  Future<void> _confirmAllOff(BuildContext context, WidgetRef ref) async {
    // "All off" here means only this master's switches — no mesh-wide
    // confirm needed (that's the overflow's kill-all). Fire directly.
    await _setAll(ref, false);
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
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
              l10n.bleTroubleBody,
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
  const _SwitchGrid({required this.switches});

  final List<SwitchState> switches;

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
          return SwitchTile(sw: switches[i])
              .animate()
              .fadeIn(duration: 260.ms, delay: (40 * i).ms)
              .slideY(begin: 0.15, curve: Curves.easeOut);
        }, childCount: switches.length),
      ),
    );
  }
}

/// One relay. Renders the optimistic override when present, else the
/// snapshot state. Animated accent glow + press feedback when on.
/// Public for widget tests.
class SwitchTile extends ConsumerStatefulWidget {
  const SwitchTile({required this.sw, super.key});

  final SwitchState sw;

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
    final online = sw.online;
    final stateLabel = online
        ? (on ? l10n.switchOn : l10n.switchOff)
        : l10n.switchOffline;

    final accent = UnisyncColors.accent;

    return Semantics(
      label: '${sw.name.isEmpty ? sw.id : sw.name}, $stateLabel',
      button: online,
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
            onTap: online ? () => _toggle(on) : null,
            onLongPress: () {
              // Rename is a Wi-Fi-only flow (BLE spec §Not supported).
              if (_guardWifi(context, ref)) {
                showRenameSwitchSheet(context, ref, sw);
              }
            },
            onTapDown: online ? (_) => setState(() => _pressed = true) : null,
            onTapUp: online ? (_) => setState(() => _pressed = false) : null,
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
      await ref
          .read(activeControlProvider)
          .setRelay(id: sw.id, on: next, ch: sw.ch);
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
