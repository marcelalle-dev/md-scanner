import 'package:equatable/equatable.dart';

enum CodeContentType {
  url,
  wifi,
  email,
  phone,
  sms,
  geo,
  contact,
  event,
  product,
  text,
}

/// What a scanned value means, with the fields worth showing.
class CodeContent extends Equatable {
  const CodeContent({
    required this.type,
    required this.raw,
    this.uri,
    this.wifiName,
    this.wifiPassword,
  });

  final CodeContentType type;
  final String raw;

  /// URI to hand to the system for types that can be opened.
  final Uri? uri;
  final String? wifiName;
  final String? wifiPassword;

  @override
  List<Object?> get props => [type, raw, uri, wifiName, wifiPassword];
}

/// Recognizes the standard payloads found in QR codes and barcodes.
abstract final class CodeContentParser {
  static final RegExp _digits = RegExp(r'^\d{8}$|^\d{12,13}$');

  static CodeContent parse(String raw, {bool linearBarcode = false}) {
    final value = raw.trim();
    final lower = value.toLowerCase();

    if (lower.startsWith('wifi:')) {
      final fields = _wifiFields(value.substring(5));
      return CodeContent(
        type: CodeContentType.wifi,
        raw: raw,
        wifiName: fields['S'],
        wifiPassword: fields['P'],
      );
    }
    if (lower.startsWith('begin:vcard') || lower.startsWith('mecard:')) {
      return CodeContent(type: CodeContentType.contact, raw: raw);
    }
    if (lower.startsWith('begin:vevent') ||
        lower.startsWith('begin:vcalendar')) {
      return CodeContent(type: CodeContentType.event, raw: raw);
    }
    if (lower.startsWith('matmsg:')) {
      return CodeContent(type: CodeContentType.email, raw: raw);
    }
    if (linearBarcode && _digits.hasMatch(value)) {
      return CodeContent(type: CodeContentType.product, raw: raw);
    }

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && !value.contains(RegExp(r'\s'))) {
      final type = switch (uri.scheme.toLowerCase()) {
        'http' || 'https' => CodeContentType.url,
        'mailto' => CodeContentType.email,
        'tel' => CodeContentType.phone,
        'sms' || 'smsto' => CodeContentType.sms,
        'geo' => CodeContentType.geo,
        // Any other scheme is still a link: the safety analysis decides
        // whether it may be opened.
        _ => CodeContentType.url,
      };
      return CodeContent(type: type, raw: raw, uri: uri);
    }
    if (RegExp(
      r'^www\.[^\s]+\.[a-z]{2,}',
      caseSensitive: false,
    ).hasMatch(value)) {
      return CodeContent(
        type: CodeContentType.url,
        raw: raw,
        uri: Uri.tryParse('https://$value'),
      );
    }
    return CodeContent(type: CodeContentType.text, raw: raw);
  }

  /// Splits `T:WPA;S:name;P:pass;;`, honouring backslash escapes.
  static Map<String, String> _wifiFields(String body) {
    final fields = <String, String>{};
    final current = StringBuffer();
    var escaped = false;
    void flush() {
      final entry = current.toString();
      current.clear();
      final separator = entry.indexOf(':');
      if (separator > 0) {
        fields[entry.substring(0, separator).toUpperCase()] = entry.substring(
          separator + 1,
        );
      }
    }

    for (final char in body.split('')) {
      if (escaped) {
        current.write(char);
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == ';') {
        flush();
      } else {
        current.write(char);
      }
    }
    flush();
    return fields;
  }
}

enum UrlRisk {
  noTls,
  ipHost,
  punycode,
  userInfo,
  manySubdomains,
  shortener,
  unusualPort,
  veryLong,
  executable,
}

enum UrlSafetyLevel { safe, caution, dangerous, blocked }

class UrlVerdict extends Equatable {
  const UrlVerdict(this.level, [this.risks = const []]);

  final UrlSafetyLevel level;
  final List<UrlRisk> risks;

  bool get canOpen => level != UrlSafetyLevel.blocked;

  @override
  List<Object?> get props => [level, risks];
}

/// Local heuristics on a scanned link. No network call is ever made: the
/// verdict only helps the user decide, it does not certify a site.
abstract final class UrlSafetyAnalyzer {
  /// Schemes that can run code or reach local data: never opened.
  static const Set<String> blockedSchemes = {
    'javascript',
    'data',
    'vbscript',
    'file',
    'content',
    'intent',
    'blob',
    'about',
    'android-app',
    'chrome',
    'view-source',
  };

  static const Set<String> _openableSchemes = {
    'http',
    'https',
    'mailto',
    'tel',
    'sms',
    'smsto',
    'geo',
  };

  static const Set<String> _shorteners = {
    'bit.ly',
    'tinyurl.com',
    't.co',
    'goo.gl',
    'ow.ly',
    'is.gd',
    'buff.ly',
    'rebrand.ly',
    'cutt.ly',
    'shorturl.at',
    'rb.gy',
    't.ly',
  };

  static const List<String> _executables = [
    '.apk',
    '.exe',
    '.msi',
    '.bat',
    '.cmd',
    '.scr',
    '.jar',
    '.dmg',
    '.sh',
  ];

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  static UrlVerdict analyze(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (blockedSchemes.contains(scheme) || !_openableSchemes.contains(scheme)) {
      return const UrlVerdict(UrlSafetyLevel.blocked);
    }
    if (scheme != 'http' && scheme != 'https') {
      return const UrlVerdict(UrlSafetyLevel.safe);
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final risks = <UrlRisk>[
      if (scheme == 'http') UrlRisk.noTls,
      if (_ipv4.hasMatch(host) || host.contains(':')) UrlRisk.ipHost,
      if (host.split('.').any((label) => label.startsWith('xn--')) ||
          host.runes.any((rune) => rune > 127))
        UrlRisk.punycode,
      if (uri.userInfo.isNotEmpty) UrlRisk.userInfo,
      if (host.split('.').length > 4) UrlRisk.manySubdomains,
      if (_shorteners.contains(host)) UrlRisk.shortener,
      if (uri.hasPort && uri.port != 80 && uri.port != 443) UrlRisk.unusualPort,
      if (uri.toString().length > 200) UrlRisk.veryLong,
      if (_executables.any(path.endsWith)) UrlRisk.executable,
    ];
    if (risks.isEmpty) return const UrlVerdict(UrlSafetyLevel.safe);

    const severe = {
      UrlRisk.userInfo,
      UrlRisk.punycode,
      UrlRisk.executable,
      UrlRisk.ipHost,
    };
    final dangerous = risks.any(severe.contains) || risks.length >= 3;
    return UrlVerdict(
      dangerous ? UrlSafetyLevel.dangerous : UrlSafetyLevel.caution,
      risks,
    );
  }
}
