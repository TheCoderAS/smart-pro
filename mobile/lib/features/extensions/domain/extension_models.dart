import 'package:freezed_annotation/freezed_annotation.dart';

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
  }) = _ExtensionInfo;

  factory ExtensionInfo.fromJson(Map<String, dynamic> json) =>
      _$ExtensionInfoFromJson(json);
}
