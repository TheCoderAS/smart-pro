import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/features/audit/data/audit_parse.dart';

void main() {
  // Firmware v11.19.0 writes audit strings for display; the app renders
  // them verbatim (changelog: "Render audit strings as-is").
  test('BLE v2 shape {events:[{t,what}]} → the what strings, verbatim', () {
    final lines = parseAuditBody({
      'events': [
        {'t': 3812, 'what': 'Signed in'},
        {'t': 4000, 'what': 'Turned all switches off'},
      ],
    });
    expect(lines, ['Signed in', 'Turned all switches off']);
  });

  test('plain JSON array of strings', () {
    expect(parseAuditBody(['a', 'b']), ['a', 'b']);
  });

  test('object with a legacy list key', () {
    expect(parseAuditBody({'log': ['x', 'y']}), ['x', 'y']);
  });

  test('plain text splits on newlines, blank lines dropped', () {
    expect(parseAuditBody('one\n\ntwo\n'), ['one', 'two']);
  });

  test('null → empty', () {
    expect(parseAuditBody(null), isEmpty);
  });
}
