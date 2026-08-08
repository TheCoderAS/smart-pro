/// Turns an audit body — from `GET /api/audit` or the BLE `audit`
/// command — into display lines. The exact shape is firmware-defined, so
/// parsing is tolerant: a JSON array becomes entries; an object with a
/// known list field (`events`, `audit`, …) is unwrapped; plain text
/// splits on newlines. BLE v2 returns `{events:[{t,what}]}` where `t` is
/// uptime seconds — we render `what` (relative time is not shown; the
/// master has no RTC).
List<String> parseAuditBody(dynamic data) {
  if (data == null) return const [];
  if (data is List) {
    return [for (final e in data) _line(e)];
  }
  if (data is Map) {
    for (final key in const ['events', 'audit', 'log', 'entries', 'lines']) {
      final inner = data[key];
      if (inner is List) return [for (final e in inner) _line(e)];
    }
    return [data.toString()];
  }
  return data
      .toString()
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
}

/// Firmware v11.19.0 writes audit strings for display ("Signed in",
/// "Turned all switches off") — the app renders them as-is, no mapping
/// or reformatting (changelog: Action required #7).
String _line(dynamic e) {
  if (e is Map) {
    final what = e['what'];
    if (what != null) return what.toString();
  }
  return e.toString();
}
