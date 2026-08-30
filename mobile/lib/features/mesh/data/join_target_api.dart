import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/endpoints.dart';
import '../../../core/api/failure.dart';
import '../../../core/logging/log.dart';

final joinTargetApiProvider = Provider<JoinTargetApi>((ref) => JoinTargetApi());

/// Talks to the switch being ADDED to a mesh — a master that is not, and
/// never becomes, this app's home.
///
/// It gets its own Dio on purpose. The app's shared client attaches the
/// home's session token to everything, and that token means nothing here:
/// tokens are per-device, so it would earn a 401 and, worse, look like
/// the home rejecting us. Nothing this class learns is persisted either —
/// no vault entry, no registry row. The new switch is joining the mesh,
/// not moving in.
class JoinTargetApi {
  JoinTargetApi() : _dio = Dio(_options);

  static final _options = BaseOptions(
    baseUrl: Api.baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 10),
    contentType: Headers.formUrlEncodedContentType,
    validateStatus: (_) => true,
  );

  final Dio _dio;

  /// Who is answering on the master address right now, and whether they
  /// are in a mesh. `/api/info` is open, so this needs no token — which
  /// is the point: it works on a switch we have never signed in to, and
  /// on one we no longer hold a session for.
  Future<({String uid, bool mesh, int meshId})> identity() async {
    final res = await _dio.get<Map<String, dynamic>>(Api.info);
    _throwIfBad(res);
    final data = res.data ?? const <String, dynamic>{};
    return (
      uid: (data['uid'] as String? ?? '').toUpperCase(),
      mesh: data['mesh'] as bool? ?? false,
      meshId: (data['mesh_id'] as num?)?.toInt() ?? 0,
    );
  }

  /// The uid of whatever is answering on the master address right now.
  /// Read before anything else: it is how the app later recognises this
  /// switch, whether from the mesh's peer list or from the switch itself.
  Future<String> uid() async => (await identity()).uid;

  /// Signs in with the password from the new switch's card. The token
  /// lives in this object for the length of the flow and is never stored.
  Future<String> login(String password) async {
    final res = await _dio.post<Map<String, dynamic>>(
      Api.login,
      data: {'password': password},
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const Unauthorized();
    }
    if (res.statusCode == 423) throw const LockedOut();
    _throwIfBad(res);
    final token = res.data?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const ServerFailure(200, 'no token in reply');
    }
    return token;
  }

  /// Hands over the invite. The reply only says the request was SENT:
  /// the master then talks to the mesh over its own radio, and the
  /// outcome of that never comes back over HTTP. Proof lives in the
  /// mesh's peer list, checked once the phone is home again.
  Future<void> join({
    required String token,
    required String mac,
    required String pin,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      Api.meshJoin,
      data: {'mac': mac, 'pin': pin},
      options: Options(headers: {Api.authHeader: token}),
    );
    if (res.statusCode == 401) throw const Unauthorized();
    _throwIfBad(res);
    log.i('mesh join request delivered to the new switch');
  }

  void _throwIfBad(Response<dynamic> res) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    final body = res.data;
    final message = body is Map && body['error'] is String
        ? body['error'] as String
        : '$body';
    throw ServerFailure(code, message);
  }
}
