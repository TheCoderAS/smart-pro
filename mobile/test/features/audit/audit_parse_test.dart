import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/features/audit/data/audit_parse.dart';

void main() {
  test('BLE v2 shape: {events:[{t,what}]} → the what strings', () {
    final lines = parseAuditBody({
      'events': [
        {'t': 3812, 'what': 'login ok'},
        {'t': 4000, 'what': 'relay ext0_1 on'},
      ],
    });
    expect(lines, ['login ok', 'relay ext0_1 on']);
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
