import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/settings_store.dart';
import 'package:md_scanner/features/ai_assistant/domain/ai_assistant.dart';
import 'package:md_scanner/features/premium/domain/billing.dart';

import '../../helpers/test_database.dart';

void main() {
  group('LocalExtractor', () {
    test('spots French and English dates', () {
      final findings = LocalExtractor.extract(
        'Fait le 27/11/2026 à Cotonou. Échéance : 1er décembre 2026, '
        'ou 2026-12-15. Signed on March 3, 2027. Référence 12345.',
      );

      expect(findings.dates, [
        '27/11/2026',
        '1er décembre 2026',
        '2026-12-15',
        'March 3, 2027',
      ]);
    });

    test('spots amounts in several currencies, once each', () {
      final findings = LocalExtractor.extract(
        'Total : 1 250,50 € TTC. Acompte 25 000 FCFA. Fee \$19.99. '
        'Total : 1 250,50 € à payer. Page 12 sur 40.',
      );

      expect(findings.amounts, ['1 250,50 €', '25 000 FCFA', '\$19.99']);
    });

    test('finds nothing in plain prose', () {
      expect(
        LocalExtractor.extract('Bonjour, voici mon courrier.').isEmpty,
        isTrue,
      );
    });
  });

  group('renderAiResult', () {
    test('turns structured output into readable text', () {
      final text = renderAiResult({
        'summary': 'Avis d\'imposition.',
        'keyPoints': ['Montant dû', 'Date limite'],
        'dates': [
          {'label': 'Échéance', 'value': '2026-12-15'},
        ],
        'missing': null,
      });

      expect(text, contains('Summary : Avis d\'imposition.'));
      expect(text, contains('Key points'));
      expect(text, contains('• Montant dû'));
      expect(text, contains('• Échéance — 2026-12-15'));
      expect(text, isNot(contains('null')));
    });
  });

  group('AiAssistantService', () {
    late AppDatabase database;
    late SettingsStore settings;
    late List<http.Request> requests;

    setUp(() async {
      database = await openTestDatabase();
      settings = SettingsStore(database.db);
      requests = [];
    });
    tearDown(() => database.close());

    AiAssistantService service(
      http.Response Function(http.Request request) respond, {
      String baseUrl = 'https://api.example.test',
      ActivePurchase? purchase = const ActivePurchase(
        productId: PremiumProducts.yearly,
        token: 'purchase-token',
      ),
    }) => AiAssistantService(
      baseUrl: baseUrl,
      settings: settings,
      activePurchase: () => purchase,
      client: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );

    http.Response ok(Object result) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'result': result,
          'quota': {'remaining': 7},
        }),
      ),
      200,
    );

    test(
      'sends text only, with the install id and the purchase proof',
      () async {
        final answer = (await service((_) => ok({'summary': 'Résumé é'})).run(
          task: AiTask.qa,
          documentText: 'Texte du document',
          outputLanguage: 'fr',
          question: 'Quel montant ?',
        )).valueOrNull!;

        expect(answer.text, 'Summary : Résumé é');
        expect(answer.remainingToday, 7);
        final request = requests.single;
        expect(request.url.toString(), 'https://api.example.test/v1/ai/tasks');
        expect(request.headers['authorization'], 'Bearer purchase-token');
        expect(request.headers['x-product-id'], PremiumProducts.yearly);
        expect(
          request.headers['x-install-id'],
          matches(RegExp(r'^[0-9a-f-]{36}$')),
        );
        expect(jsonDecode(request.body), {
          'task': 'qa',
          'outputLanguage': 'fr',
          'documentText': 'Texte du document',
          'question': 'Quel montant ?',
        });
      },
    );

    test('keeps the same install id across calls', () async {
      final assistant = service((_) => ok({'a': 1}));
      await assistant.run(
        task: AiTask.summary,
        documentText: 'x',
        outputLanguage: 'en',
      );
      await assistant.run(
        task: AiTask.summary,
        documentText: 'x',
        outputLanguage: 'en',
      );

      expect(
        requests[0].headers['x-install-id'],
        requests[1].headers['x-install-id'],
      );
    });

    test('does nothing when no backend is configured', () async {
      final assistant = service((_) => ok({}), baseUrl: '');

      expect(assistant.isConfigured, isFalse);
      final result = await assistant.run(
        task: AiTask.summary,
        documentText: 'x',
        outputLanguage: 'fr',
      );
      expect(
        result.failureOrNull,
        const NetworkFailure(NetworkFailureKind.notConfigured),
      );
      expect(requests, isEmpty);
    });

    test('maps server answers to typed failures', () async {
      Future<Failure?> failureFor(int status) async =>
          (await service(
                (_) => http.Response('{"error":{"code":"x"}}', status),
              ).run(
                task: AiTask.summary,
                documentText: 'x',
                outputLanguage: 'fr',
              ))
              .failureOrNull;

      expect(
        await failureFor(403),
        const NetworkFailure(NetworkFailureKind.unauthorized, statusCode: 403),
      );
      expect(
        await failureFor(413),
        const ValidationFailure('document_too_long'),
      );
      expect(
        await failureFor(429),
        const NetworkFailure(NetworkFailureKind.quotaExceeded),
      );
      expect(
        await failureFor(503),
        const NetworkFailure(NetworkFailureKind.serverError, statusCode: 503),
      );
    });

    test('rejects a malformed answer', () async {
      final result = await service(
        (_) => http.Response('not json', 200),
      ).run(task: AiTask.summary, documentText: 'x', outputLanguage: 'fr');

      expect(
        result.failureOrNull,
        const NetworkFailure(NetworkFailureKind.invalidResponse),
      );
    });

    test('consent is off until recorded', () async {
      final assistant = service((_) => ok({}));

      expect(await assistant.hasConsent, isFalse);
      await assistant.recordConsent();
      expect(await assistant.hasConsent, isTrue);
    });
  });
}
