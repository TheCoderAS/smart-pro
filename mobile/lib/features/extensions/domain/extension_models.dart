import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/ws/state_dto.dart' show Presence;

part 'extension_models.freezed.dart';
part 'extension_models.g.dart';

/// One row of GET /api/extensions (API §5). `avail` appears only when
/// a newer firmware image is waiting; `stuck` means three failed OTA
/// attempts and the master has given up.
@freezed
abstract class ExtensionInfo with _$ExtensionInfo {
  const factory ExtensionInfo({
    required int slot,
    @Default(0) int addr,
    @Default(false) bool online,
    @Default(0) int type,
    @Default(0) int rev,
    @Default('') String fw,
    @Default('') String name,
    @Default('') String sw1,
    @Default('') String sw2,
    @Default(0) int fails,
    @Default(false) bool stuck,
    String? avail,

    /// The master's debounced presence verdict. `online` above is the same
    /// judgement as a bool; this separates a settled outage from a board
    /// that keeps dropping and returning.
    @JsonKey(name: 'presence') @Default('online') String presenceRaw,

    /// Seconds since the master last heard from this board. The master has
    /// no clock, so last-seen is always relative.
    @JsonKey(name: 'last_seen') @Default(0) int lastSeen,
  }) = _ExtensionInfo;

  const ExtensionInfo._();

  Presence get presence => Presence.parse(presenceRaw);

  factory ExtensionInfo.fromJson(Map<String, dynamic> json) =>
      _$ExtensionInfoFromJson(json);
}
