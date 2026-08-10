import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

/// GET /api/info — deliberately open; called before login to learn the
/// firmware version and confirm reachability (API §5).
///
/// `auth` here means "an owner password has been set" (ops guide §A2):
/// false is a factory-fresh master whose API is fully open and which
/// must be commissioned immediately.
@freezed
abstract class DeviceInfo with _$DeviceInfo {
  const factory DeviceInfo({
    required int uptime,
    @JsonKey(name: 'free_heap') required int freeHeap,
    required String uid,
    required String fw,
    required bool auth,

    /// The network name this master is broadcasting *right now* — its own
    /// report, not the phone's OS. Instruction copy ("connect to X") comes
    /// from here, so it self-heals after a rename and needs no location
    /// permission to read.
    @Default('') String ssid,

    /// True when this master is in a mesh. Meshed masters are one home and
    /// one switcher entry, never several.
    @Default(false) bool mesh,

    /// Stable mesh identity. The mesh name is user-changeable, so the
    /// switcher keys on this instead.
    @JsonKey(name: 'mesh_id') @Default(0) int meshId,
  }) = _DeviceInfo;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);
}

/// POST /api/login — token is 32 hex chars; `mesh` says which password
/// was accepted (device vs mesh), used for UI wording (API §2).
@freezed
abstract class LoginResult with _$LoginResult {
  const factory LoginResult({
    required String token,
    required bool mesh,
  }) = _LoginResult;

  factory LoginResult.fromJson(Map<String, dynamic> json) =>
      _$LoginResultFromJson(json);
}
