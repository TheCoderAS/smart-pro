import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/transport_coordinator.dart';
import '../../../core/transport/transport_manager.dart';
import '../../../core/widgets/connection_bar.dart';
import '../../extensions/data/extension_repository.dart';
import '../../extensions/domain/extension_models.dart';
import '../data/firmware_repository.dart';
import '../domain/firmware_models.dart';

/// Published manifests from the CDN. Unreachable CDN (normal while
/// glued to the master's AP) resolves to an empty list, not an error.
/// Over Bluetooth the phone keeps its own internet, so this is more
/// likely to succeed than on the master's Wi-Fi (BLE spec v2 §7).
final manifestsProvider =
    FutureProvider<List<FirmwareManifest>>((ref) async {
  try {
    return await ref.watch(firmwareRepositoryProvider).fetchManifests();
  } on Exception {
    return const [];
  }
});

/// The master's running version + staged images, over whichever
/// transport is active (BLE `fwlist` or HTTP). Best-effort — an error
/// (e.g. not yet connected) resolves to empty, never throws.
final firmwareStatusProvider = FutureProvider<FwStatus>((ref) async {
  try {
    return await ref.watch(activeControlProvider).fwStatus();
  } on Object {
    return const FwStatus();
  }
});

class FirmwareScreen extends ConsumerWidget {
  const FirmwareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifests = ref.watch(manifestsProvider);
    final extensions = ref.watch(extensionsProvider);
    final master = ref.watch(firmwareStatusProvider).value?.master ?? '';

    // Highest published version per extension type.
    final latestByType = <int, FirmwareManifest>{};
    for (final m in manifests.value ?? const <FirmwareManifest>[]) {
      final existing = latestByType[m.type];
      if (existing == null || _versionIsNewer(m.version, existing.version)) {
        latestByType[m.type] = m;
      }
    }
    // The master's own image is type 0; it installs through a different
    // endpoint and confirms differently, so it gets its own card.
    final masterManifest = latestByType.remove(0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firmware'),
        bottom: const ConnectionBar(),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(manifestsProvider);
          ref.invalidate(firmwareStatusProvider);
          await ref.read(extensionsProvider.notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (master.isNotEmpty && masterManifest == null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.router_outlined),
                  title: const Text('This master'),
                  subtitle: Text('Firmware $master'),
                ),
              ),
            if (masterManifest != null)
              _MasterCard(manifest: masterManifest, installed: master),
            if (manifests.value?.isEmpty ?? true)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No updates available',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Update listings need an internet connection. '
                        'While your phone is on the switch’s Wi-Fi it '
                        'may not have one — that’s normal. Pull to '
                        'refresh once you’re back online.',
                      ),
                    ],
                  ),
                ),
              ),
            for (final entry in latestByType.entries)
              _ManifestCard(
                manifest: entry.value,
                installedVersions: [
                  for (final ext
                      in extensions.value ?? const <ExtensionInfo>[])
                    if (ext.type == entry.key) ext.fw,
                ],
              ),
          ],
        ),
      ),
    );
  }
}

bool _versionIsNewer(String a, String b) {
  List<int> parse(String v) => [
        for (final part in v.split('.'))
          int.tryParse(part.replaceAll(RegExp('[^0-9]'), '')) ?? 0,
      ];
  final pa = parse(a);
  final pb = parse(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

class _ManifestCard extends ConsumerStatefulWidget {
  const _ManifestCard({
    required this.manifest,
    required this.installedVersions,
  });

  final FirmwareManifest manifest;
  final List<String> installedVersions;

  @override
  ConsumerState<_ManifestCard> createState() => _ManifestCardState();
}

class _ManifestCardState extends ConsumerState<_ManifestCard> {
  double? _progress;
  String? _status;

  /// Held between download and install, so a Bluetooth user can fetch the
  /// image now and install it when they are next on the master's Wi-Fi.
  Uint8List? _bytes;

  bool get _busy => _progress != null || _status == 'uploading';

  bool get _upToDate =>
      widget.installedVersions.isNotEmpty &&
      widget.installedVersions
          .every((v) => !_versionIsNewer(widget.manifest.version, v));

  @override
  Widget build(BuildContext context) {
    final m = widget.manifest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extension type ${m.type} — ${m.version}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _upToDate
                  ? 'All matching extensions are up to date.'
                  : 'Installed: ${widget.installedVersions.isEmpty ? "none on this master" : widget.installedVersions.toSet().join(", ")}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (m.changelog.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                m.changelog,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            if (_progress != null)
              LinearProgressIndicator(value: _progress)
            else if (_status != null)
              Text(_status!)
            else
              FilledButton.icon(
                icon: const Icon(Icons.system_update_alt),
                label: Text(
                  _bytes != null &&
                          ref.watch(currentTransportProvider) ==
                              TransportKind.ble
                      ? 'Waiting for Wi-Fi'
                      : _upToDate
                          ? 'Re-send to mesh'
                          : 'Update mesh',
                ),
                onPressed: _busy ? null : _run,
              ),
            if (_bytes != null &&
                ref.watch(currentTransportProvider) == TransportKind.ble) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref
                    .read(transportCoordinatorProvider)
                    .choose(TransportPreference.wifi),
                child: const Text('Switch to Wi-Fi to install'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(firmwareRepositoryProvider);

    // Downloading works in either mode — it uses the phone's mobile data,
    // and the master has no internet on either path. Only *installing*
    // needs the master's Wi-Fi, so a Bluetooth user gets the file now and
    // a clear "waiting for Wi-Fi" state, rather than being turned away
    // before anything has been fetched.
    if (_bytes == null) {
      setState(() {
        _progress = 0;
        _status = null;
      });
      try {
        final bytes = await repo.download(
          widget.manifest,
          onProgress: (p) => setState(() => _progress = p),
        );
        if (!mounted) return;
        setState(() {
          _bytes = bytes;
          _progress = null;
        });
      } on Exception catch (e) {
        if (!mounted) return;
        setState(() => _progress = null);
        messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
        return;
      }
    }

    if (ref.read(currentTransportProvider) == TransportKind.ble) {
      setState(() => _status = _waitingForWifi);
      return;
    }

    setState(() => _status = 'uploading');
    try {
      await repo.uploadExtensionImage(
        manifest: widget.manifest,
        bytes: _bytes!,
      );
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _status = 'Queued — switches update one at a time within about '
            '30 seconds each.';
      });
      // The verdict comes from the boards themselves, never from the
      // upload: re-read the extension list so the versions on screen are
      // the ones actually running.
      await ref.read(extensionsProvider.notifier).refresh();
    } on ServerFailure catch (e) {
      if (!mounted) return;
      setState(() => _status = null);
      messenger.showSnackBar(SnackBar(content: Text(_explainUploadError(e))));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _status = null);
      messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }
}

const _waitingForWifi = 'Downloaded — waiting for Wi-Fi to install.';

/// The master's own image. Separate from the extension cards because it
/// installs through a different endpoint and, crucially, confirms
/// differently: a master accepts an upload and secure boot decides at the
/// next restart, so success is only ever read back from the device.
class _MasterCard extends ConsumerStatefulWidget {
  const _MasterCard({required this.manifest, required this.installed});

  final FirmwareManifest manifest;
  final String installed;

  @override
  ConsumerState<_MasterCard> createState() => _MasterCardState();
}

class _MasterCardState extends ConsumerState<_MasterCard> {
  double? _progress;
  String? _status;
  Uint8List? _bytes;

  bool get _upToDate =>
      widget.installed.isNotEmpty &&
      !_versionIsNewer(widget.manifest.version, widget.installed);

  @override
  Widget build(BuildContext context) {
    final onBle =
        ref.watch(currentTransportProvider) == TransportKind.ble;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This master — ${widget.manifest.version}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _upToDate
                  ? 'Running ${widget.installed}. Up to date.'
                  : 'Running ${widget.installed.isEmpty ? "an unknown version" : widget.installed}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.manifest.changelog.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(widget.manifest.changelog),
            ],
            const SizedBox(height: 12),
            if (_progress != null)
              LinearProgressIndicator(value: _progress)
            else if (_status != null)
              Text(_status!)
            else
              FilledButton.icon(
                icon: const Icon(Icons.system_update_alt),
                label: Text(
                  _bytes != null && onBle
                      ? 'Waiting for Wi-Fi'
                      : _upToDate
                          ? 'Re-install'
                          : 'Update this master',
                ),
                onPressed: _run,
              ),
            if (_bytes != null && onBle) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref
                    .read(transportCoordinatorProvider)
                    .choose(TransportPreference.wifi),
                child: const Text('Switch to Wi-Fi to install'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(firmwareRepositoryProvider);

    if (_bytes == null) {
      setState(() {
        _progress = 0;
        _status = null;
      });
      try {
        final bytes = await repo.download(
          widget.manifest,
          onProgress: (p) => setState(() => _progress = p),
        );
        if (!mounted) return;
        setState(() {
          _bytes = bytes;
          _progress = null;
        });
      } on Exception catch (e) {
        if (!mounted) return;
        setState(() => _progress = null);
        messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
        return;
      }
    }

    if (ref.read(currentTransportProvider) == TransportKind.ble) {
      setState(() => _status = _waitingForWifi);
      return;
    }

    setState(() => _status = 'Sending to the master…');
    try {
      await repo.uploadMasterImage(_bytes!);
      if (!mounted) return;
      // A master image is not signature-checked on upload — secure boot
      // decides at the next boot. A 200 proves nothing, so wait for it to
      // come back and read the version it is actually running.
      setState(() => _status = 'Restarting — confirming the version…');
      final running = await repo.confirmMasterVersion();
      if (!mounted) return;
      final ok = !_versionIsNewer(widget.manifest.version, running);
      setState(() {
        _bytes = ok ? null : _bytes;
        _status = ok
            ? 'Updated. Now running $running.'
            : 'The master restarted still running $running — it rejected '
                'the image.';
      });
      ref.invalidate(firmwareStatusProvider);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Update failed: $e');
    }
  }
}

/// Plain-English wording for the API §7 upload error bodies.
String _explainUploadError(ServerFailure e) {
  return switch (e.errorMessage) {
    'missing signature' =>
      'The update file is missing its signature — try re-downloading.',
    'not a Unisync extension image' =>
      'That file is not a Unisync extension image.',
    'image not in signed library' =>
      'The master rejected an unsigned image.',
    _ =>
      'The master rejected the image (possibly a bad signature). Code ${e.status}.',
  };
}
