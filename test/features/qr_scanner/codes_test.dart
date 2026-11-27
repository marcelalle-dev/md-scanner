import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/features/qr_scanner/data/code_history_repository.dart';
import 'package:md_scanner/features/qr_scanner/domain/code_content.dart';
import 'package:md_scanner/features/qr_scanner/presentation/code_generator_screen.dart';

import '../../helpers/test_database.dart';

void main() {
  group('CodeContentParser', () {
    CodeContentType typeOf(String raw, {bool linear = false}) =>
        CodeContentParser.parse(raw, linearBarcode: linear).type;

    test('recognizes the standard payloads', () {
      expect(typeOf('https://example.org/a?b=1'), CodeContentType.url);
      expect(typeOf('www.example.org'), CodeContentType.url);
      expect(typeOf('mailto:a@example.org'), CodeContentType.email);
      expect(typeOf('MATMSG:TO:a@example.org;SUB:Hi;;'), CodeContentType.email);
      expect(typeOf('tel:+22990000000'), CodeContentType.phone);
      expect(typeOf('SMSTO:+22990000000:Bonjour'), CodeContentType.sms);
      expect(typeOf('geo:6.37,2.39'), CodeContentType.geo);
      expect(typeOf('BEGIN:VCARD\nFN:Ada\nEND:VCARD'), CodeContentType.contact);
      expect(
        typeOf('BEGIN:VEVENT\nSUMMARY:x\nEND:VEVENT'),
        CodeContentType.event,
      );
      expect(typeOf('Bonjour le monde'), CodeContentType.text);
      expect(typeOf('3017620422003', linear: true), CodeContentType.product);
      expect(typeOf('3017620422003'), CodeContentType.text);
    });

    test('reads Wi-Fi fields including escaped characters', () {
      final wifi = CodeContentParser.parse(
        r'WIFI:T:WPA;S:Maison\;Bleue;P:p\:ss\\word;;',
      );

      expect(wifi.type, CodeContentType.wifi);
      expect(wifi.wifiName, 'Maison;Bleue');
      expect(wifi.wifiPassword, r'p:ss\word');
    });

    test('adds https to bare web addresses', () {
      expect(
        CodeContentParser.parse('www.example.org/page').uri,
        Uri.parse('https://www.example.org/page'),
      );
    });
  });

  group('UrlSafetyAnalyzer', () {
    UrlVerdict analyze(String url) => UrlSafetyAnalyzer.analyze(Uri.parse(url));

    test('a plain https site is safe', () {
      expect(
        analyze('https://www.example.org/path'),
        const UrlVerdict(UrlSafetyLevel.safe),
      );
    });

    test('blocks schemes that can run code or read local data', () {
      for (final url in [
        'javascript:alert(1)',
        'data:text/html,<script>',
        'file:///sdcard/secret.txt',
        'intent://scan/#Intent;scheme=zxing;end',
        'content://contacts/people',
        'market://details?id=x',
      ]) {
        final verdict = analyze(url);
        expect(verdict.level, UrlSafetyLevel.blocked, reason: url);
        expect(verdict.canOpen, isFalse, reason: url);
      }
    });

    test('flags each risk', () {
      expect(analyze('http://example.org').risks, [UrlRisk.noTls]);
      expect(analyze('https://192.168.1.10/login').risks, [UrlRisk.ipHost]);
      expect(analyze('https://xn--pple-43d.com').risks, [UrlRisk.punycode]);
      expect(analyze('https://bank.com@evil.example').risks, [
        UrlRisk.userInfo,
      ]);
      expect(analyze('https://a.b.c.d.example.org').risks, [
        UrlRisk.manySubdomains,
      ]);
      expect(analyze('https://bit.ly/x').risks, [UrlRisk.shortener]);
      expect(analyze('https://example.org:8443/').risks, [UrlRisk.unusualPort]);
      expect(analyze('https://example.org/app.apk').risks, [
        UrlRisk.executable,
      ]);
      expect(analyze('https://example.org/${'a' * 220}').risks, [
        UrlRisk.veryLong,
      ]);
    });

    test('grades the overall level', () {
      expect(analyze('http://example.org').level, UrlSafetyLevel.caution);
      expect(analyze('https://bit.ly/x').level, UrlSafetyLevel.caution);
      expect(
        analyze('https://bank.com@evil.example').level,
        UrlSafetyLevel.dangerous,
      );
      expect(
        analyze('http://10.0.0.1:8080/x.apk').level,
        UrlSafetyLevel.dangerous,
      );
    });

    test('non-web actions stay openable', () {
      expect(analyze('tel:+22990000000').canOpen, isTrue);
      expect(analyze('mailto:a@example.org').level, UrlSafetyLevel.safe);
    });
  });

  group('generator', () {
    test('builds standard QR payloads', () {
      expect(buildQrPayload(QrTemplate.text, ' Salut '), 'Salut');
      expect(
        buildQrPayload(QrTemplate.url, 'example.org'),
        'https://example.org',
      );
      expect(buildQrPayload(QrTemplate.url, 'http://a.b'), 'http://a.b');
      expect(buildQrPayload(QrTemplate.email, 'a@b.c'), 'mailto:a@b.c');
      expect(buildQrPayload(QrTemplate.phone, '+229 90 00'), 'tel:+2299000');
      expect(
        buildQrPayload(QrTemplate.wifi, 'Box;1', wifiPassword: 'a:b'),
        r'WIFI:T:WPA;S:Box\;1;P:a\:b;;',
      );
      expect(
        buildQrPayload(QrTemplate.wifi, 'Libre'),
        'WIFI:T:nopass;S:Libre;;',
      );
      expect(buildQrPayload(QrTemplate.text, '   '), '');
    });

    test('a generated Wi-Fi payload is read back identically', () {
      final payload = buildQrPayload(
        QrTemplate.wifi,
        r'Chez "Léa"; 5G',
        wifiPassword: r'p@ss;w\rd',
      );
      final parsed = CodeContentParser.parse(payload);

      expect(parsed.wifiName, r'Chez "Léa"; 5G');
      expect(parsed.wifiPassword, r'p@ss;w\rd');
    });

    test('validates data against each symbology', () {
      expect(GeneratorFormat.qr.accepts('n\'importe quoi é'), isTrue);
      expect(GeneratorFormat.ean13.accepts('3017620422003'), isTrue);
      expect(GeneratorFormat.ean13.accepts('3017620422004'), isFalse);
      expect(GeneratorFormat.ean13.accepts('12AB'), isFalse);
      expect(GeneratorFormat.ean8.accepts('96385074'), isTrue);
      expect(GeneratorFormat.code39.accepts('ABC-123'), isTrue);
      expect(GeneratorFormat.code39.accepts('abc'), isFalse);
      expect(GeneratorFormat.code128.accepts('Colis 42'), isTrue);
      for (final format in GeneratorFormat.values) {
        expect(format.accepts(''), isFalse, reason: format.label);
      }
    });
  });

  group('CodeHistoryRepository', () {
    late AppDatabase database;
    late CodeHistoryRepository history;
    var now = DateTime.utc(2026, 11, 27, 10);

    setUp(() async {
      database = await openTestDatabase();
      history = CodeHistoryRepository(
        database.db,
        clock: () => now = now.add(const Duration(minutes: 1)),
      );
    });

    tearDown(() async {
      await history.dispose();
      await database.close();
    });

    test('keeps entries newest first and skips an immediate repeat', () async {
      await history.add(
        content: 'A',
        format: 'QR Code',
        kind: CodeHistoryKind.scanned,
      );
      await history.add(
        content: 'A',
        format: 'QR Code',
        kind: CodeHistoryKind.scanned,
      );
      await history.add(
        content: 'B',
        format: 'EAN-13',
        kind: CodeHistoryKind.scanned,
      );
      await history.add(
        content: 'A',
        format: 'QR Code',
        kind: CodeHistoryKind.scanned,
      );
      await history.add(
        content: 'G',
        format: 'QR Code',
        kind: CodeHistoryKind.generated,
      );

      final all = (await history.list()).valueOrNull!;
      expect(all.map((entry) => entry.content), ['G', 'A', 'B', 'A']);
      final scanned = (await history.list(
        kind: CodeHistoryKind.scanned,
      )).valueOrNull!;
      expect(scanned, hasLength(3));
      expect(scanned.first.date.isAfter(scanned.last.date), isTrue);
    });

    test('deletes one entry, then everything, and notifies', () async {
      var notifications = 0;
      final subscription = history.changes.listen((_) => notifications++);
      await history.add(
        content: 'A',
        format: 'QR Code',
        kind: CodeHistoryKind.scanned,
      );
      await history.add(
        content: 'B',
        format: 'QR Code',
        kind: CodeHistoryKind.scanned,
      );
      final first = (await history.list()).valueOrNull!.first;

      await history.delete(first.id);
      expect((await history.list()).valueOrNull, hasLength(1));
      await history.clear();
      expect((await history.list()).valueOrNull, isEmpty);

      await pumpEventQueue();
      expect(notifications, 4);
      await subscription.cancel();
    });
  });
}
