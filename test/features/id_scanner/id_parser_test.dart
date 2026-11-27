import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/features/document_vault/presentation/document_organize.dart';
import 'package:md_scanner/features/id_scanner/domain/id_parser.dart';

void main() {
  final now = DateTime(2026, 11, 27);

  group('IdParser', () {
    test('computes ICAO check digits', () {
      expect(IdParser.checkDigit('L898902C3'), 6);
      expect(IdParser.checkDigit('740812'), 2);
      expect(IdParser.checkDigit('120415'), 9);
      expect(IdParser.checkDigit('D23145890'), 7);
    });

    test('reads a passport zone (TD3)', () {
      final fields = IdParser.parse('''
PASSPORT  UTOPIA
Some printed text 12 AUG 1974
P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
L898902C36UTO7408122F1204159ZE184226B<<<<<10
''', now: now);

      expect(fields.surname, 'ERIKSSON');
      expect(fields.givenNames, 'ANNA MARIA');
      expect(fields.documentNumber, 'L898902C3');
      expect(fields.nationality, 'UTO');
      expect(fields.birthDate, '12/08/1974');
      expect(fields.expiryDate, '15/04/2012');
      expect(fields.sex, 'F');
      expect(fields.mrzChecksValid, isTrue);
    });

    test('reads an identity card zone (TD1), even with OCR spaces', () {
      final fields = IdParser.parse('''
I<UTOD231458907<<<<<<<<<<<<<<<
7408122F1204159UTO<<<<<<<<<<<6
ERIKSSON<<ANNA<MARIA <<<<<<<<<<
''', now: now);

      expect(fields.surname, 'ERIKSSON');
      expect(fields.givenNames, 'ANNA MARIA');
      expect(fields.documentNumber, 'D23145890');
      expect(fields.birthDate, '12/08/1974');
      expect(fields.expiryDate, '15/04/2012');
      expect(fields.mrzChecksValid, isTrue);
    });

    test('reads a TD2 zone', () {
      final fields = IdParser.parse('''
I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<
D231458907UTO7408122F1204159<<<<<<<6
''', now: now);

      expect(fields.surname, 'ERIKSSON');
      expect(fields.documentNumber, 'D23145890');
      expect(fields.mrzChecksValid, isTrue);
    });

    test('flags a zone whose check digit does not match', () {
      final fields = IdParser.parse('''
P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
L898902C46UTO7408122F1204159ZE184226B<<<<<10
''', now: now);

      expect(fields.hasMrz, isTrue);
      expect(fields.mrzChecksValid, isFalse);
    });

    test('a recent birth year is not pushed into the past century', () {
      final fields = IdParser.parse('''
P<UTODOE<<JOHN<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
X123456785UTO1501010M3001019<<<<<<<<<<<<<<00
''', now: now);

      expect(fields.birthDate, '01/01/2015');
      expect(fields.expiryDate, '01/01/2030');
    });

    test('without a zone, lists the dates and numbers it can spot', () {
      final fields = IdParser.parse(
        'CARTE NATIONALE\nNom: DUPONT\nNé le 03/05/1990\nN° 1234AB5678\n'
        'Valable jusqu\'au 02/05/2030',
        now: now,
      );

      expect(fields.hasMrz, isFalse);
      expect(fields.otherDates, ['03/05/1990', '02/05/2030']);
      expect(fields.otherNumbers, contains('1234AB5678'));
      expect(fields.isEmpty, isFalse);
    });

    test('plain text yields nothing', () {
      expect(IdParser.parse('Bonjour tout le monde', now: now).isEmpty, isTrue);
    });
  });

  group('parseTagInput', () {
    test('trims, drops blanks and de-duplicates ignoring case', () {
      expect(parseTagInput(' Factures, 2026 ,, factures , Impôts'), [
        'Factures',
        '2026',
        'Impôts',
      ]);
      expect(parseTagInput('  '), isEmpty);
    });
  });
}
