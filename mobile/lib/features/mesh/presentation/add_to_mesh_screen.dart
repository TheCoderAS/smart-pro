import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/logging/log.dart';
import '../../../core/platform/radios.dart';
import '../../../core/widgets/password_field.dart';
import '../application/mesh_join_mode.dart';
import '../data/join_target_api.dart';
import '../data/mesh_repository.dart';
import '../domain/mesh_models.dart';

/// Adding a second switch to the mesh, guided step by step.
///
/// The phone can only talk to one master at a time, and the two masters
/// talk to each other over their own radio — so this is unavoidably a
/// walk: fetch an invite here, carry it to the new switch, come back.
/// The app cannot make that shorter, so it makes it legible instead, and
/// never claims a step worked when it does not know that.
///
/// Joining networks is the phone's own Wi-Fi settings throughout. The
/// app-driven join is gone from setup for good reason — Android's system
/// dialog kept reporting "no available networks" while the switch was
/// beaconing away — and this flow is not the place to resurrect it.
enum _Step { invite, deliver, rejoin, done }

class AddToMeshScreen extends ConsumerStatefulWidget {
  const AddToMeshScreen({super.key});

  @override
  ConsumerState<AddToMeshScreen> createState() => _AddToMeshScreenState();
}

class _AddToMeshScreenState extends ConsumerState<AddToMeshScreen> {
  _Step _step = _Step.invite;
  MeshInvite? _invite;
  DateTime? _inviteFetchedAt;
  String _meshName = '';

  /// The uid read off the new switch while we were on its network — the
  /// only way to recognise it later among the mesh's peers.
  String? _joinerUid;
  String _joinerName = 'the new switch';

  final _passController = TextEditingController();
  bool _busy = false;
  String? _error;
  Timer? _clock;

  /// The invite is good for five minutes (firmware
  /// MESH_PIN_VALID_MS). That covers the walk to Wi-Fi settings and
  /// back; past it the master refuses the join, and only the mesh can
  /// issue a fresh one — which means going back to the mesh network.
  static const _inviteLife = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    ref.read(meshJoinModeProvider.notifier).enter();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _step != _Step.done) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchInvite());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _passController.dispose();
    // Whatever happened, the app goes back to trusting its own home.
    ref.read(meshJoinModeProvider.notifier).leave();
    super.dispose();
  }

  Duration get _inviteLeft {
    final at = _inviteFetchedAt;
    if (at == null) return Duration.zero;
    final left = _inviteLife - DateTime.now().difference(at);
    return left.isNegative ? Duration.zero : left;
  }

  bool get _inviteExpired => _invite != null && _inviteLeft == Duration.zero;

  Future<void> _fetchInvite() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Both from the master we are still connected to — this is the
      // last thing that needs the mesh's own network.
      final status = await ref.read(meshRepositoryProvider).status();
      final invite = await ref.read(meshRepositoryProvider).invite();
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _inviteFetchedAt = DateTime.now();
        _meshName = status.meshName;
      });
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.describe());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Step 2: we are on the new switch's own network now. Sign in with the
  /// password from its card — its token, not the home's — and hand over
  /// the invite.
  Future<void> _deliverInvite() async {
    final invite = _invite;
    if (invite == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(joinTargetApiProvider);
    try {
      final uid = await api.uid();
      final token = await api.login(_passController.text);
      await api.join(token: token, mac: invite.mac, pin: invite.pin);
      _passController.clear();
      if (!mounted) return;
      setState(() {
        _joinerUid = uid;
        _joinerName = 'switch $uid';
        _step = _Step.rejoin;
      });
    } on Unauthorized {
      if (mounted) {
        setState(() => _error =
            "That password didn't work. It is the one printed on the new "
            "switch's card — the same one you just used to join its "
            'network.');
      }
    } on LockedOut {
      if (mounted) {
        setState(() => _error = 'Too many wrong passwords. The switch '
            'locks out for about five minutes.');
      }
    } on Unreachable {
      if (mounted) {
        setState(() => _error = "The new switch didn't answer. Check the "
            'phone is on its network in Wi-Fi settings — it is the one '
            'named on its card.');
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.describe());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Step 3: the honest one. The join happens between the two masters
  /// over their own radio and no HTTP reply ever carries its outcome, so
  /// the only real proof is the new switch appearing in the mesh's peer
  /// list. Ask the mesh, don't ask the user.
  Future<void> _verifyJoined() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final uid = _joinerUid;
    try {
      // A freshly joined master needs a moment to be counted.
      for (var attempt = 1; attempt <= 4; attempt++) {
        try {
          final status = await ref.read(meshRepositoryProvider).status();
          final found = uid == null
              ? status.peers.isNotEmpty
              : status.peers.any((p) => p.uid.toUpperCase() == uid);
          if (found) {
            log.i('mesh join confirmed: $uid is a peer of "${status.meshName}"');
            ref.invalidate(meshStatusProvider);
            if (mounted) setState(() => _step = _Step.done);
            return;
          }
          log.d('mesh join not confirmed yet (attempt $attempt)');
        } on ApiFailure catch (e) {
          log.d('mesh status unreachable during verify: ${e.describe()}');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (mounted) {
        setState(() => _error =
            'The mesh has not picked up $_joinerName yet.\n\nCheck the phone '
            'is back on "$_meshName", and that the new switch is close '
            'enough to another one — they talk to each other directly, not '
            'through your phone. You can try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add a switch'),
          // No ConnectionBar here on purpose: for most of this flow the
          // phone is on another master's network and the home is out of
          // reach by design. A red bar would be alarming and wrong.
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _StepDots(step: _step),
              const SizedBox(height: 24),
              ...switch (_step) {
                _Step.invite => _inviteStep(context),
                _Step.deliver => _deliverStep(context),
                _Step.rejoin => _rejoinStep(context),
                _Step.done => _doneStep(context),
              },
              if (_error != null) ...[
                const SizedBox(height: 20),
                _ErrorNote(message: _error!),
              ],
              const SizedBox(height: 32),
              if (_step != _Step.done)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _inviteStep(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _invite != null && !_inviteExpired;
    return [
      Text('Power on the new switch', style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(
        'Put it where it will live and switch it on. Keep it within reach '
        'of one of your existing switches — they talk to each other '
        'directly, not through your phone.',
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 20),
      if (_busy && _invite == null)
        const Center(child: CircularProgressIndicator())
      else if (ready) ...[
        _InviteClock(left: _inviteLeft),
        const SizedBox(height: 20),
        Text(
          'Now open your Wi-Fi settings and join the new switch\'s own '
          'network — its name and password are on the card in its box.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.wifi),
          label: const Text("Open the phone's Wi-Fi settings"),
          onPressed: () => ref.read(radiosProvider).openWifiSettings(),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.arrow_forward),
          label: const Text("I've joined the new switch"),
          onPressed: () => setState(() {
            _error = null;
            _step = _Step.deliver;
          }),
        ),
      ] else if (_inviteExpired) ...[
        Text(
          'The invite has expired. A new one has to come from the mesh, so '
          'rejoin "$_meshName" first, then ask again.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Get a new invite'),
          onPressed: _busy ? null : _fetchInvite,
        ),
      ] else
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
          onPressed: _busy ? null : _fetchInvite,
        ),
    ];
  }

  List<Widget> _deliverStep(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text('Hand over the invite', style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(
        "Type the new switch's password — the one from its card, the same "
        'one you just used to join its network. It signs the app in for '
        'this one step and is never saved.',
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 8),
      _InviteClock(left: _inviteLeft),
      const SizedBox(height: 16),
      PasswordField(
        controller: _passController,
        label: "The new switch's password",
        helper: 'From the card in its box.',
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send),
        label: const Text('Send the invite'),
        onPressed: _busy || _inviteExpired ? null : _deliverInvite,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _step = _Step.invite),
        child: const Text('Back'),
      ),
    ];
  }

  List<Widget> _rejoinStep(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text('Come back to your home network',
          style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(
        'The invite is delivered. The new switch is taking on the mesh\'s '
        'name and password now, so its own network has disappeared — that '
        'is expected.\n\nRejoin "$_meshName" in your Wi-Fi settings, then '
        'come back and confirm.',
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        icon: const Icon(Icons.wifi),
        label: const Text("Open the phone's Wi-Fi settings"),
        onPressed: () => ref.read(radiosProvider).openWifiSettings(),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: Text(_busy ? 'Checking the mesh…' : "I'm back on \"$_meshName\""),
        onPressed: _busy ? null : _verifyJoined,
      ),
    ];
  }

  List<Widget> _doneStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return [
      Icon(Icons.hub_rounded, size: 48, color: scheme.primary),
      const SizedBox(height: 16),
      Text('Added to "$_meshName"', style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(
        'The mesh can see the new switch. It is on the home screen with '
        'the rest, and its switches work from any room.',
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 24),
      FilledButton(
        // Straight home: the mesh screen behind this one is about to be
        // rebuilt from a status this flow already invalidated.
        onPressed: () =>
            Navigator.of(context).popUntil((r) => r.isFirst),
        child: const Text('Done'),
      ),
    ];
  }
}

class _InviteClock extends StatelessWidget {
  const _InviteClock({required this.left});

  final Duration left;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final low = left.inSeconds <= 60;
    final m = left.inMinutes;
    final s = left.inSeconds % 60;
    return Row(
      children: [
        Icon(Icons.timer_outlined,
            size: 16, color: low ? scheme.error : scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          left == Duration.zero
              ? 'The invite has expired'
              : 'Invite valid for $m:${s.toString().padLeft(2, "0")}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: low ? scheme.error : scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = _Step.values.indexOf(step);
    return Row(
      children: [
        for (var i = 0; i < _Step.values.length; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= index ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < _Step.values.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
