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
  return [
    for (final l in data.toString().split('\n'))
      if (l.trim().isNotEmpty) prettifyAuditText(l),
  ];
}

String _line(dynamic e) {
  if (e is Map) {
    final what = e['what'];
    if (what != null) return prettifyAuditText(what.toString());
  }
  return prettifyAuditText(e.toString());
}

/// Renders a firmware audit string ("login ok") as a normal sentence
/// ("Login OK."): sentence case, common tokens expanded, terminal
/// punctuation. Pure string work so it's easy to unit-test.
String prettifyAuditText(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  // Expand/normalise common firmware tokens (word-boundary, any case).
  const swaps = <String, String>{
    'ok': 'OK',
    'fail': 'failed',
    'auth': 'authentication',
    'pwd': 'password',
    'ota': 'OTA',
    'cfg': 'config',
  };
  s = s.replaceAllMapped(RegExp(r'\b([A-Za-z]+)\b'), (m) {
    final word = m[1]!;
    final repl = swaps[word.toLowerCase()];
    return repl ?? word;
  });
  // Sentence case: capitalise the first letter, leave the rest.
  s = s[0].toUpperCase() + s.substring(1);
  // Terminal punctuation.
  if (!RegExp(r'[.!?]$').hasMatch(s)) s = '$s.';
  return s;
}
