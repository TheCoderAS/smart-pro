/// Every path the master serves, from UNISYNC_API_REFERENCE_v1.md §5.
///
/// The master is always `192.168.4.1` — including after roaming to a
/// different master in the mesh (same SSID, same IP, see API §3).
/// REST on port 80, WebSocket on port 81.
abstract final class Api {
  static const host = '192.168.4.1';
  static const baseUrl = 'http://$host';
  static const wsUrl = 'ws://$host:81/ws';

  // Device
  static const info = '/api/info'; // OPEN
  static const login = '/api/login'; // OPEN, password
  static const logout = '/api/logout'; // OPEN, server no-op
  static const password = '/api/password'; // TOKEN, password
  static const masterRename = '/api/master/rename'; // TOKEN, name
  static const audit = '/api/audit'; // TOKEN
  static const scan = '/api/scan'; // TOKEN

  // Switches
  static const relay = '/api/relay'; // TOKEN, id + state + ch
  static const relayKillAll = '/api/relay/killall'; // TOKEN
  static const switchRename = '/api/switch/rename'; // TOKEN, id + name
  static const switchRestore = '/api/switch/restore'; // TOKEN, id + restore
  static const switchReorder = '/api/switch/reorder'; // TOKEN, plain

  // Extensions
  static const extensions = '/api/extensions'; // TOKEN
  static const assign = '/api/assign'; // TOKEN, uid + name
  static const reject = '/api/reject'; // TOKEN, uid
  static const replace = '/api/replace'; // TOKEN, uid + slot + name
  static const rename = '/api/rename'; // TOKEN, slot + name
  static const remove = '/api/remove'; // TOKEN, slot

  // Mesh
  static const meshStatus = '/api/mesh/status'; // TOKEN
  static const meshCreate = '/api/mesh/create'; // TOKEN, name
  static const meshInvite = '/api/mesh/invite'; // TOKEN
  static const meshJoin = '/api/mesh/join'; // TOKEN, mac + pin
  static const meshLeave = '/api/mesh/leave'; // TOKEN
  static const meshKick = '/api/mesh/kick'; // TOKEN, uid (online only)
  static const meshRename = '/api/mesh/rename'; // TOKEN, name
  static const meshPasswd = '/api/mesh/passwd'; // TOKEN, old + pass + name
  static const meshRelay = '/api/mesh/relay'; // TOKEN, peer_uid + sw_id + ch
  static const meshConfig = '/api/mesh/config'; // TOKEN, cmd + target_uid + …

  // Firmware
  static const fwList = '/api/fw/list'; // TOKEN
  static const fwUpload = '/api/fw/upload'; // TOKEN, multipart + sig/sec/mesh
  static const otaMaster = '/api/ota/master'; // TOKEN, multipart
  static const otaExtension = '/api/ota/extension'; // TOKEN, multipart + addr
  // /api/ota/image is master-to-master only; the app never calls it.
  static const provision = '/api/provision'; // OPEN until set, root + fw

  /// Auth header carrying the session token (API §2).
  static const authHeader = 'X-Auth';

  /// Query key alternative to the header — required for the WebSocket,
  /// whose handshake cannot carry headers.
  static const tokenQueryKey = 't';
}

/// BLE recovery GATT identifiers, from UNISYNC_API_REFERENCE_v1.md §8.
/// Advertised device name is `U{UID}`, e.g. `UC5F77720`.
abstract final class RecoveryBle {
  static const service = '556e6973-796e-6320-5265-636f76657231';
  static const challengeChar = '556e6973-796e-6320-5265-636f76657232';
  static const responseChar = '556e6973-796e-6320-5265-636f76657233';
  static const resultChar = '556e6973-796e-6320-5265-636f76657234';
}
