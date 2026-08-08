import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/features/audit/data/audit_parse.dart';

void main() {
  group('prettifyAuditText', () {
    test('sentence-cases, expands tokens, adds terminal punctuation', () {
      expect(prettifyAuditText('login ok'), 'Login OK.');
      expect(prettifyAuditText('auth fail'), 'Authentication failed.');
      expect(prettifyAuditText('ota start'), 'OTA start.');
    });

    test('keeps existing terminal punctuation', () {
      expect(prettifyAuditText('rebooted!'), 'Rebooted!');
    });

    test('empty stays empty', () {
      expect(prettifyAuditText('   '), '');
    });
  });

  group('parseAuditBody', () {
    test('BLE v2 shape {events:[{t,what}]} → prettified what strings', () {
      final lines = parseAuditBody({
        'events': [
          {'t': 3812, 'what': 'login ok'},
          {'t': 4000, 'what': 'relay ext0_1 on'},
        ],
      });
      expect(lines, ['Login OK.', 'Relay ext0_1 on.']);
    });

    test('plain JSON array of strings, prettified', () {
      expect(parseAuditBody(['reboot', 'scan done']),
          ['Reboot.', 'Scan done.']);
    });

    test('object with a legacy list key', () {
      expect(parseAuditBody({'log': ['x', 'y']}), ['X.', 'Y.']);
    });

    test('plain text splits on newlines, blank lines dropped', () {
      expect(parseAuditBody('one\n\ntwo\n'), ['One.', 'Two.']);
    });

    test('null → empty', () {
      expect(parseAuditBody(null), isEmpty);
    });
  });
}
