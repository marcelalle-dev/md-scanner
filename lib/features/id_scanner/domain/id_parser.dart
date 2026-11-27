import 'package:equatable/equatable.dart';
import 'package:md_scanner/features/ai_assistant/domain/ai_assistant.dart'
    show LocalExtractor;

/// Information read on an identity document.
///
/// It is a reading aid only: values come from OCR and may be wrong, and
/// nothing here says anything about the authenticity of the document.
class IdFields extends Equatable {
  const IdFields({
    this.surname,
    this.givenNames,
    this.documentNumber,
    this.birthDate,
    this.expiryDate,
    this.nationality,
    this.sex,
    this.mrzChecksValid,
    this.otherDates = const [],
    this.otherNumbers = const [],
  });

  final String? surname;
  final String? givenNames;
  final String? documentNumber;

  /// `DD/MM/YYYY`.
  final String? birthDate;
  final String? expiryDate;

  /// Three-letter code as printed in the machine-readable zone.
  final String? nationality;
  final String? sex;

  /// Null when no machine-readable zone was found; otherwise whether every
  /// check digit of the zone matched.
  final bool? mrzChecksValid;
  final List<String> otherDates;
  final List<String> otherNumbers;

  bool get hasMrz => mrzChecksValid != null;

  bool get isEmpty => !hasMrz && otherDates.isEmpty && otherNumbers.isEmpty;

  @override
  List<Object?> get props => [
    surname,
    givenNames,
    documentNumber,
    birthDate,
    expiryDate,
    nationality,
    sex,
    mrzChecksValid,
    otherDates,
    otherNumbers,
  ];
}

/// Reads identity documents from OCR text. Supports the ICAO 9303
/// machine-readable zones (passports TD3, cards TD1 and TD2), which makes it
/// work for documents of any country that carry one; without a zone it falls
/// back to listing the dates and numbers it can spot.
abstract final class IdParser {
  static final RegExp _mrzLine = RegExp(r'^[A-Z0-9<]{28,46}$');
  static final RegExp _number = RegExp(r'\b(?=[A-Z0-9]*\d{3})[A-Z0-9]{6,}\b');

  static IdFields parse(String text, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final lines = [
      for (final raw in text.split('\n'))
        raw.toUpperCase().replaceAll('«', '<<').replaceAll(RegExp(r'\s'), ''),
    ].where(_mrzLine.hasMatch).toList();

    final mrz = _td3(lines, today) ?? _td1(lines, today) ?? _td2(lines, today);
    if (mrz != null) return mrz;

    final seen = <String>{};
    return IdFields(
      otherDates: LocalExtractor.extract(text).dates,
      otherNumbers: [
        for (final match in _number.allMatches(text.toUpperCase()))
          if (seen.add(match.group(0)!)) match.group(0)!,
      ],
    );
  }

  /// ICAO 9303 check digit: weights 7, 3, 1 over digits, letters (A = 10)
  /// and fillers (0).
  static int checkDigit(String value) {
    const weights = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      final digit = switch (code) {
        >= 0x30 && <= 0x39 => code - 0x30,
        >= 0x41 && <= 0x5A => code - 0x41 + 10,
        _ => 0,
      };
      sum += digit * weights[i % 3];
    }
    return sum % 10;
  }

  static bool _checks(String value, String digit) =>
      int.tryParse(digit) == checkDigit(value);

  static IdFields? _td3(List<String> lines, DateTime now) {
    for (var i = 0; i + 1 < lines.length; i++) {
      final a = lines[i];
      final b = lines[i + 1];
      if (a.length != 44 || b.length != 44 || !a.startsWith('P')) continue;
      return _build(
        names: a.substring(5),
        number: b.substring(0, 9),
        numberCheck: b[9],
        nationality: b.substring(10, 13),
        birth: b.substring(13, 19),
        birthCheck: b[19],
        sex: b[20],
        expiry: b.substring(21, 27),
        expiryCheck: b[27],
        now: now,
      );
    }
    return null;
  }

  static IdFields? _td1(List<String> lines, DateTime now) {
    for (var i = 0; i + 2 < lines.length; i++) {
      final a = lines[i];
      final b = lines[i + 1];
      final c = lines[i + 2];
      if (a.length != 30 || b.length != 30 || c.length != 30) continue;
      return _build(
        names: c,
        number: a.substring(5, 14),
        numberCheck: a[14],
        nationality: b.substring(15, 18),
        birth: b.substring(0, 6),
        birthCheck: b[6],
        sex: b[7],
        expiry: b.substring(8, 14),
        expiryCheck: b[14],
        now: now,
      );
    }
    return null;
  }

  static IdFields? _td2(List<String> lines, DateTime now) {
    for (var i = 0; i + 1 < lines.length; i++) {
      final a = lines[i];
      final b = lines[i + 1];
      if (a.length != 36 || b.length != 36) continue;
      return _build(
        names: a.substring(5),
        number: b.substring(0, 9),
        numberCheck: b[9],
        nationality: b.substring(10, 13),
        birth: b.substring(13, 19),
        birthCheck: b[19],
        sex: b[20],
        expiry: b.substring(21, 27),
        expiryCheck: b[27],
        now: now,
      );
    }
    return null;
  }

  static IdFields _build({
    required String names,
    required String number,
    required String numberCheck,
    required String nationality,
    required String birth,
    required String birthCheck,
    required String sex,
    required String expiry,
    required String expiryCheck,
    required DateTime now,
  }) {
    final parts = names.split('<<');
    String clean(String value) =>
        value.replaceAll('<', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final surname = clean(parts.first);
    final given = parts.length > 1 ? clean(parts.sublist(1).join(' ')) : '';
    return IdFields(
      surname: surname.isEmpty ? null : surname,
      givenNames: given.isEmpty ? null : given,
      documentNumber: clean(number).replaceAll(' ', ''),
      birthDate: _date(birth, now, isBirth: true),
      expiryDate: _date(expiry, now, isBirth: false),
      nationality: clean(nationality),
      sex: switch (sex) {
        'M' || 'F' => sex,
        _ => null,
      },
      mrzChecksValid:
          _checks(number, numberCheck) &&
          _checks(birth, birthCheck) &&
          _checks(expiry, expiryCheck),
    );
  }

  /// `YYMMDD` to `DD/MM/YYYY`. A birth year cannot be in the future; an
  /// expiry is assumed to fall in the current century.
  static String? _date(String value, DateTime now, {required bool isBirth}) {
    final yy = int.tryParse(value.substring(0, 2));
    final mm = int.tryParse(value.substring(2, 4));
    final dd = int.tryParse(value.substring(4, 6));
    if (yy == null || mm == null || dd == null) return null;
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
    final century = (now.year ~/ 100) * 100;
    var year = century + yy;
    if (isBirth && year > now.year) year -= 100;
    return '${dd.toString().padLeft(2, '0')}/${mm.toString().padLeft(2, '0')}/$year';
  }
}
