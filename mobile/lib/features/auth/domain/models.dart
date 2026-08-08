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
